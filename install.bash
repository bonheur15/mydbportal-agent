#!/bin/bash

# Database Server Setup Script
# This script installs MySQL, PostgreSQL, MongoDB, and Nginx with SSL configuration
# Only the agent gets a domain - databases are accessible via direct IP:port
# Modify this on your own risk, and ensure you have backups of your data before running it.

set -e  # Exit on any error

# Configuration
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/")
CREDENTIALS_FILE="credentials"
INSTALL_LOG="install.log"
NGINX_LOG="nginx_setup.log"
API_ENDPOINT="https://mydpportal.com/api/jobs/setup-server"
AGENT_PORT="8273"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$INSTALL_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$INSTALL_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$INSTALL_LOG"
}

# Function to generate secure password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to encrypt credentials
encrypt_credentials() {
    local data="$1"
    echo "$data" | openssl enc -aes-256-cbc -a -salt -pass pass:"$ENCRYPTION_KEY"
}

# Function to decrypt credentials
decrypt_credentials() {
    local encrypted_data="$1"
    echo "$encrypted_data" | openssl enc -aes-256-cbc -d -a -pass pass:"$ENCRYPTION_KEY"
}

# Function to get server IP
get_server_ip() {
    curl -s ifconfig.me || curl -s ipecho.net/plain || curl -s icanhazip.com
}

# Function to install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."
    
    # Update system
    apt-get update -y >> "$INSTALL_LOG" 2>&1
    
    # Install required packages
    apt-get install -y \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        openssl \
        jq \
        certbot \
        python3-certbot-nginx >> "$INSTALL_LOG" 2>&1
    
    log "Prerequisites installed successfully"
}

# Function to install MySQL
install_mysql() {
    log "Installing MySQL..."
    
    # Generate MySQL root password
    MYSQL_ROOT_PASSWORD=$(generate_password)
    
    # Set non-interactive installation
    export DEBIAN_FRONTEND=noninteractive
    echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
    
    # Install MySQL
    apt-get install -y mysql-server >> "$INSTALL_LOG" 2>&1
    
    # Start and enable MySQL
    systemctl start mysql >> "$INSTALL_LOG" 2>&1
    systemctl enable mysql >> "$INSTALL_LOG" 2>&1
    
    # Secure MySQL installation
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF >> "$INSTALL_LOG" 2>&1
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE USER 'admin'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    
    # Configure MySQL for remote access
    sed -i 's/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
    
    # Restart MySQL
    systemctl restart mysql >> "$INSTALL_LOG" 2>&1
    
    # Store credentials
    echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" >> temp_credentials.txt
    echo "MYSQL_ADMIN_USER=admin" >> temp_credentials.txt
    echo "MYSQL_ADMIN_PASSWORD=$MYSQL_ROOT_PASSWORD" >> temp_credentials.txt
    echo "MYSQL_PORT=3306" >> temp_credentials.txt
    
    log "MySQL installed and configured successfully"
}

# Function to install PostgreSQL
install_postgresql() {
    log "Installing PostgreSQL..."
    
    # Generate PostgreSQL password
    POSTGRES_PASSWORD=$(generate_password)
    
    # Install PostgreSQL
    apt-get install -y postgresql postgresql-contrib >> "$INSTALL_LOG" 2>&1
    
    # Start and enable PostgreSQL
    systemctl start postgresql >> "$INSTALL_LOG" 2>&1
    systemctl enable postgresql >> "$INSTALL_LOG" 2>&1
    
    # Configure PostgreSQL
    sudo -u postgres psql <<EOF >> "$INSTALL_LOG" 2>&1
ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';
CREATE USER admin WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
EOF
    
    # Configure PostgreSQL for remote access
    POSTGRES_VERSION=$(pg_config --version | awk '{print $2}' | sed 's/\..*//')
    POSTGRES_CONFIG_DIR="/etc/postgresql/$POSTGRES_VERSION/main"
    
    # Update postgresql.conf
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$POSTGRES_CONFIG_DIR/postgresql.conf"
    
    # Update pg_hba.conf
    echo "host all all 0.0.0.0/0 md5" >> "$POSTGRES_CONFIG_DIR/pg_hba.conf"
    
    # Restart PostgreSQL
    systemctl restart postgresql >> "$INSTALL_LOG" 2>&1
    
    # Store credentials
    echo "POSTGRES_SUPERUSER=postgres" >> temp_credentials.txt
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> temp_credentials.txt
    echo "POSTGRES_ADMIN_USER=admin" >> temp_credentials.txt
    echo "POSTGRES_ADMIN_PASSWORD=$POSTGRES_PASSWORD" >> temp_credentials.txt
    echo "POSTGRES_PORT=5432" >> temp_credentials.txt
    
    log "PostgreSQL installed and configured successfully"
}

# Function to install MongoDB
install_mongodb() {
    log "Installing MongoDB..."
    
    # Generate MongoDB password
    MONGO_PASSWORD=$(generate_password)
    
    # Import MongoDB GPG key
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor >> "$INSTALL_LOG" 2>&1
    
    # Add MongoDB repository
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list >> "$INSTALL_LOG" 2>&1
    
    # Update package list
    apt-get update -y >> "$INSTALL_LOG" 2>&1
    
    # Install MongoDB
    apt-get install -y mongodb-org >> "$INSTALL_LOG" 2>&1
    
    # Start and enable MongoDB
    systemctl start mongod >> "$INSTALL_LOG" 2>&1
    systemctl enable mongod >> "$INSTALL_LOG" 2>&1
    
    # Configure MongoDB authentication
    mongosh --eval "
    use admin
    db.createUser({
        user: 'admin',
        pwd: '$MONGO_PASSWORD',
        roles: [ { role: 'root', db: 'admin' } ]
    })
    " >> "$INSTALL_LOG" 2>&1
    
    # Enable authentication
    sed -i 's/#security:/security:\n  authorization: enabled/' /etc/mongod.conf
    
    # Configure for remote access
    sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
    
    # Restart MongoDB
    systemctl restart mongod >> "$INSTALL_LOG" 2>&1
    
    # Store credentials
    echo "MONGO_ADMIN_USER=admin" >> temp_credentials.txt
    echo "MONGO_ADMIN_PASSWORD=$MONGO_PASSWORD" >> temp_credentials.txt
    echo "MONGO_PORT=27017" >> temp_credentials.txt
    
    log "MongoDB installed and configured successfully"
}

# Function to install Nginx
install_nginx() {
    log "Installing Nginx..."
    
    # Install Nginx
    apt-get install -y nginx >> "$INSTALL_LOG" 2>&1
    
    # Start and enable Nginx
    systemctl start nginx >> "$INSTALL_LOG" 2>&1
    systemctl enable nginx >> "$INSTALL_LOG" 2>&1
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    log "Nginx installed successfully"
}

# Function to call API and get server slug
call_setup_api() {   

    SERVER_IP=$(get_server_ip)
    
    # Call API for demo now - this is a placeholder
    RESPONSE=$(curl -s -X POST "https://$API_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "{\"server_ip\": \"$SERVER_IP\"}")
    
    # Extract server name slug from response
    SERVER_NAME_SLUG=$(echo "$RESPONSE" | jq -r '.server_name_slug')
    # SERVER_NAME_SLUG="demo-server"
    
    if [ "$SERVER_NAME_SLUG" = "null" ] || [ -z "$SERVER_NAME_SLUG" ]; then
        log_error "Failed to get server name slug from API response"
        exit 1
    fi
    
    echo "$SERVER_NAME_SLUG"
}

# Function to configure Nginx with SSL (Agent only)
configure_nginx_ssl() {
    local server_slug="$1"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Configuring Nginx with SSL for agent..." >> "$NGINX_LOG"
    
    # Define agent domain only
    AGENT_DOMAIN="agent-$server_slug.mydbportal.com"
    
    # Create Nginx configuration for agent only
    cat > /etc/nginx/sites-available/agent <<EOF
# Agent HTTP proxy
server {
    listen 80;
    server_name $AGENT_DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:$AGENT_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Default server block to handle other requests
server {
    listen 80 default_server;
    server_name _;
    return 444;
}
EOF

    # Enable site
    ln -sf /etc/nginx/sites-available/agent /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Testing Nginx configuration..." >> "$NGINX_LOG"
    if nginx -t >> "$NGINX_LOG" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Nginx configuration test passed" >> "$NGINX_LOG"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Nginx configuration test failed" >> "$NGINX_LOG"
        log_error "Nginx configuration test failed. Check $NGINX_LOG for details."
        exit 1
    fi
    
    # Reload Nginx
    systemctl reload nginx >> "$NGINX_LOG" 2>&1
    
    # Obtain SSL certificate for agent domain
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Obtaining SSL certificate for agent..." >> "$NGINX_LOG"
    
    certbot --nginx --non-interactive --agree-tos --email admin@mydbportal.com \
        -d "$AGENT_DOMAIN" >> "$NGINX_LOG" 2>&1
    
    # Store domain information
    echo "AGENT_DOMAIN=$AGENT_DOMAIN" >> temp_credentials.txt
    
    log "SSL certificate configured successfully for agent"
}

# Function to setup agent service
setup_agent() {
    log "Setting up agent service..."
    
    # Create agent directory
    mkdir -p /opt/database-agent
    
    # Create agent script
    cat > /opt/database-agent/agent.py <<EOF
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import subprocess
from datetime import datetime

PORT = $AGENT_PORT

class AgentHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            # Check database status
            mysql_status = self.check_service_status('mysql')
            postgres_status = self.check_service_status('postgresql')
            mongodb_status = self.check_service_status('mongod')
            
            status = {
                'status': 'running',
                'timestamp': datetime.now().isoformat(),
                'server_ip': self.get_server_ip(),
                'databases': {
                    'mysql': {
                        'status': mysql_status,
                        'port': 3306,
                        'connection': f"{self.get_server_ip()}:3306"
                    },
                    'postgresql': {
                        'status': postgres_status,
                        'port': 5432,
                        'connection': f"{self.get_server_ip()}:5432"
                    },
                    'mongodb': {
                        'status': mongodb_status,
                        'port': 27017,
                        'connection': f"{self.get_server_ip()}:27017"
                    }
                }
            }
            
            self.wfile.write(json.dumps(status, indent=2).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def check_service_status(self, service_name):
        try:
            result = subprocess.run(['systemctl', 'is-active', service_name], 
                                  capture_output=True, text=True)
            return 'running' if result.returncode == 0 else 'stopped'
        except:
            return 'unknown'
    
    def get_server_ip(self):
        try:
            result = subprocess.run(['curl', '-s', 'ifconfig.me'], 
                                  capture_output=True, text=True, timeout=5)
            return result.stdout.strip() if result.returncode == 0 else 'unknown'
        except:
            return 'unknown'

with socketserver.TCPServer(("", PORT), AgentHandler) as httpd:
    print(f"Agent server running on port {PORT}")
    httpd.serve_forever()
EOF

    # Make agent executable
    chmod +x /opt/database-agent/agent.py
    
    # Create systemd service
    cat > /etc/systemd/system/database-agent.service <<EOF
[Unit]
Description=Database Agent Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/database-agent
ExecStart=/usr/bin/python3 /opt/database-agent/agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Start and enable agent service
    systemctl daemon-reload
    systemctl start database-agent
    systemctl enable database-agent
    
    log "Agent service configured and started"
}

# Function to encrypt and store credentials
store_credentials() {
    log "Storing encrypted credentials..."
    
    # Add server information
    echo "SERVER_IP=$(get_server_ip)" >> temp_credentials.txt
    echo "SERVER_NAME_SLUG=$SERVER_NAME_SLUG" >> temp_credentials.txt
    echo "SETUP_DATE=$(date)" >> temp_credentials.txt
    
    # Encrypt credentials
    ENCRYPTED_CREDENTIALS=$(encrypt_credentials "$(cat temp_credentials.txt)")
    
    # Store encrypted credentials
    echo "$ENCRYPTED_CREDENTIALS" > "$CREDENTIALS_FILE"
    
    # Clean up temporary file
    rm temp_credentials.txt
    
    log "Credentials encrypted and stored in $CREDENTIALS_FILE"
}

# Function to test decryption
test_decryption() {
    log "Testing credential decryption..."
    
    if [ -f "$CREDENTIALS_FILE" ]; then
        DECRYPTED=$(decrypt_credentials "$(cat $CREDENTIALS_FILE)")
        echo "Decrypted credentials:"
        echo "$DECRYPTED"
        log "Credential decryption test successful"
    else
        log_error "Credentials file not found"
    fi
}

# Main execution
main() {
    log "Starting database server setup..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Install prerequisites
    install_prerequisites
    
    # Install databases
    install_mysql
    install_postgresql
    install_mongodb
    log "Databases installed successfully"
    # Install Nginx
    install_nginx
    
    # Call API to get server slug
    SERVER_NAME_SLUG=$(call_setup_api)
    
    # Configure Nginx with SSL (agent only)
    configure_nginx_ssl "$SERVER_NAME_SLUG"
    
    # Setup agent
    setup_agent
    
    # Store credentials
    store_credentials
    
    # Test decryption
    test_decryption
    
    log "Database server setup completed successfully!"
    log "Credentials stored in: $CREDENTIALS_FILE"
    log "Install log: $INSTALL_LOG"
    log "Nginx log: $NGINX_LOG"
    log "Agent running on port: $AGENT_PORT"
    
    SERVER_IP=$(get_server_ip)
    
    echo ""
    echo "Setup Summary:"
    echo "=============="
    echo "Server IP: $SERVER_IP"
    echo "Agent Domain: agent-$SERVER_NAME_SLUG.mydbportal.com"
    echo ""
    echo "Database Connections:"
    echo "MySQL:      $SERVER_IP:3306"
    echo "PostgreSQL: $SERVER_IP:5432"
    echo "MongoDB:    $SERVER_IP:27017 (if enabled)"
    echo ""
    echo "Example MySQL connection:"
    echo "mysql -u admin -p -h $SERVER_IP -P 3306"
    echo ""
    echo "To decrypt credentials, run:"
    echo "cat $CREDENTIALS_FILE | openssl enc -aes-256-cbc -d -a -pass pass:$ENCRYPTION_KEY"
}

# Execute main function
main "$@"
