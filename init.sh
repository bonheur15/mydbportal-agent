#!/bin/bash

# Database Server Setup Script
# This script installs MySQL, PostgreSQL, and MongoDB.
# Databases and the agent are accessible via direct IP:port.
# Modify this on your own risk, and ensure you have backups of your data before running it.

set -e  # Exit on any error

# Configuration
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/")
CREDENTIALS_FILE="credentials"
INSTALL_LOG="install.log"
API_ENDPOINT="https://mydpportal.com/api/jobs/setup-server"
AGENT_PORT="8273"

# Database credentials (will be generated during installation)
MYSQL_ROOT_PASSWORD=""
POSTGRES_PASSWORD=""
MONGO_PASSWORD=""

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
    
    # Install required packages (Nginx and Certbot removed)
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
        python3 >> "$INSTALL_LOG" 2>&1
    
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
    log "Starting MongoDB service..."
    systemctl start mongod >> "$INSTALL_LOG" 2>&1
    systemctl enable mongod >> "$INSTALL_LOG" 2>&1
    
    # Wait for MongoDB service to be ready before proceeding
    log "Waiting for MongoDB to initialize..."
    for i in {1..30}; do
        # Use mongosh to ping the server. &> /dev/null silences output.
        if mongosh --eval "db.adminCommand('ping')" &> /dev/null; then
            log "MongoDB service is active."
            break
        fi
        log "Waiting... attempt $i of 30"
        sleep 2
    done

    # Final check, if it's still not running, exit with an error
    if ! mongosh --eval "db.adminCommand('ping')" &> /dev/null; then
        log_error "MongoDB service failed to start. Check logs with 'journalctl -u mongod'"
        journalctl -u mongod -n 50 --no-pager >> "$INSTALL_LOG"
        exit 1
    fi
    
    # Configure MongoDB authentication now that the service is confirmed running
    log "Configuring MongoDB admin user..."
    mongosh --eval "
    use admin
    db.createUser({
        user: 'admin',
        pwd: '$MONGO_PASSWORD',
        roles: [ { role: 'root', db: 'admin' } ]
    })
    " >> "$INSTALL_LOG" 2>&1
    
    # Enable authentication and configure for remote access
    # This sed command finds the commented #security line and replaces it with an enabled block
    sed -i '/#security:/a\security:\n  authorization: enabled' /etc/mongod.conf
    sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
    
    # Restart MongoDB to apply security and network changes
    log "Restarting MongoDB to apply new configuration..."
    systemctl restart mongod >> "$INSTALL_LOG" 2>&1
    
    # Store credentials
    echo "MONGO_ADMIN_USER=admin" >> temp_credentials.txt
    echo "MONGO_ADMIN_PASSWORD=$MONGO_PASSWORD" >> temp_credentials.txt
    echo "MONGO_PORT=27017" >> temp_credentials.txt
    
    log "MongoDB installed and configured successfully"
}

# Function to call API and send credentials
call_setup_api() {
    SERVER_IP=$(get_server_ip)

    # Construct the JSON payload with database credentials
    JSON_PAYLOAD=$(cat <<EOF
{
  "server_ip": "$SERVER_IP",
  "agent_token": "$AGENT_TOKEN",
  "credentials": {
    "mysql": {
      "user": "admin",
      "password": "$MYSQL_ROOT_PASSWORD",
      "port": 3306
    },
    "postgresql": {
      "user": "admin",
      "password": "$POSTGRES_PASSWORD",
      "port": 5432
    },
    "mongodb": {
      "user": "admin",
      "password": "$MONGO_PASSWORD",
      "port": 27017
    }
  }
}
EOF
)

    log "Sending setup data to API: $API_ENDPOINT"
    log "Payload: $JSON_PAYLOAD"

    RESPONSE=$(curl -s -X POST "$API_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$JSON_PAYLOAD")
    
    log "API Response: $RESPONSE"

    # Check if the response contains an error field and log it.
    if echo "$RESPONSE" | jq -e '.error' > /dev/null; then
        log_warning "API call returned an error. Please check the response in the log file above. The setup will continue."
    else
        log "API call reported success."
    fi
}

# Function to setup agent service
setup_agent() {
    log "Setting up agent service..."

    # Define agent binary URL and local path
    local agent_url="https://github.com/bonheur15/mydbportal-agent/releases/download/v0.0.1/agent-linux-x64"
    local agent_dir="/opt/database-agent"
    local agent_binary_path="$agent_dir/agent"

    # Create agent directory
    mkdir -p "$agent_dir"

    # Download the agent binary using curl
    log "Downloading agent from $agent_url..."
    if ! curl -L --fail -o "$agent_binary_path" "$agent_url"; then
        log_error "Failed to download agent binary from $agent_url"
        exit 1
    fi
    log "Agent downloaded successfully to $agent_binary_path"

    # Make the downloaded agent binary executable
    chmod +x "$agent_binary_path"

    # Create systemd service file to manage the agent
    log "Creating systemd service for the agent..."
    cat > /etc/systemd/system/database-agent.service <<EOF
[Unit]
Description=MyDbPortal Agent Service
Documentation=https://github.com/bonheur15/mydbportal-agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$agent_dir
ExecStart=$agent_binary_path
Restart=always
RestartSec=10

# Pass necessary environment variables to the agent process
Environment="AGENT_PORT=$AGENT_PORT"
Environment="AGENT_TOKEN=$AGENT_TOKEN"

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, then start and enable the new service
    log "Reloading systemd and starting agent service..."
    systemctl daemon-reload
    systemctl start database-agent
    systemctl enable database-agent

    # Check if the service started successfully
    if systemctl is-active --quiet database-agent; then
        log "Agent service is active and running."
    else
        log_error "Agent service failed to start. Check status with 'journalctl -u database-agent'"
        # Dump last few log lines for easier debugging
        journalctl -u database-agent -n 20 --no-pager >> "$INSTALL_LOG"
        exit 1
    fi
}

# Function to encrypt and store credentials
store_credentials() {
    log "Storing encrypted credentials..."
    
    # Add server information
    echo "SERVER_IP=$(get_server_ip)" >> temp_credentials.txt
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
    
    # Call API to notify completion and send credentials
    call_setup_api
    
    # Setup agent
    setup_agent
    
    # Store credentials
    store_credentials
    
    # Test decryption
    test_decryption
    
    log "Database server setup completed successfully!"
    log "Credentials stored in: $CREDENTIALS_FILE"
    log "Install log: $INSTALL_LOG"
    log "Agent running on port: $AGENT_PORT"
    
    SERVER_IP=$(get_server_ip)
    
    echo ""
    echo "Setup Summary:"
    echo "=============="
    echo "Server IP:    $SERVER_IP"
    echo "Agent URL:    http://$SERVER_IP:$AGENT_PORT"
    echo ""
    echo "Database Connections:"
    echo "MySQL:        $SERVER_IP:3306"
    echo "PostgreSQL:   $SERVER_IP:5432"
    echo "MongoDB:      $SERVER_IP:27017"
    echo ""
    echo "Example MySQL connection:"
    echo "mysql -u admin -p -h $SERVER_IP -P 3306"
    echo ""
    echo "To decrypt credentials, run:"
    echo "cat $CREDENTIALS_FILE | openssl enc -aes-256-cbc -d -a -pass pass:$ENCRYPTION_KEY"
}

# Execute main function
main "$@"