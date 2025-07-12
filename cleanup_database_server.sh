#!/bin/bash

# Database Server Cleanup Script
# This script removes MySQL, PostgreSQL, MongoDB, Nginx, and all related configurations
# WARNING: This will permanently delete all databases and configurations!

set -e  # Exit on any error

# Configuration
CREDENTIALS_FILE="credentials"
INSTALL_LOG="install.log"
NGINX_LOG="nginx_setup.log"
CLEANUP_LOG="cleanup.log"
AGENT_PORT="8273"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$CLEANUP_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$CLEANUP_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$CLEANUP_LOG"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$CLEANUP_LOG"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo -e "${RED}WARNING: This will permanently delete all databases and configurations!${NC}"
    echo -e "${RED}This includes:${NC}"
    echo "  - All MySQL databases and users"
    echo "  - All PostgreSQL databases and users"
    echo "  - All MongoDB databases and collections"
    echo "  - Nginx configuration and SSL certificates"
    echo "  - Database agent service"
    echo "  - All log files and credentials"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'YES' to confirm): " -r
    if [[ ! $REPLY == "YES" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed cleanup - proceeding with removal"
}

# Function to stop services
stop_services() {
    log "Stopping services..."
    
    # Stop database agent
    if systemctl is-active --quiet database-agent 2>/dev/null; then
        systemctl stop database-agent >> "$CLEANUP_LOG" 2>&1 || true
        log "Database agent service stopped"
    fi
    
    # Stop MySQL
    if systemctl is-active --quiet mysql 2>/dev/null; then
        systemctl stop mysql >> "$CLEANUP_LOG" 2>&1 || true
        log "MySQL service stopped"
    fi
    
    # Stop PostgreSQL
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        systemctl stop postgresql >> "$CLEANUP_LOG" 2>&1 || true
        log "PostgreSQL service stopped"
    fi
    
    # Stop MongoDB
    if systemctl is-active --quiet mongod 2>/dev/null; then
        systemctl stop mongod >> "$CLEANUP_LOG" 2>&1 || true
        log "MongoDB service stopped"
    fi
    
    # Stop Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl stop nginx >> "$CLEANUP_LOG" 2>&1 || true
        log "Nginx service stopped"
    fi
    
    log "All services stopped"
}

# Function to disable services
disable_services() {
    log "Disabling services..."
    
    # Disable database agent
    if systemctl is-enabled --quiet database-agent 2>/dev/null; then
        systemctl disable database-agent >> "$CLEANUP_LOG" 2>&1 || true
        log "Database agent service disabled"
    fi
    
    # Disable MySQL
    if systemctl is-enabled --quiet mysql 2>/dev/null; then
        systemctl disable mysql >> "$CLEANUP_LOG" 2>&1 || true
        log "MySQL service disabled"
    fi
    
    # Disable PostgreSQL
    if systemctl is-enabled --quiet postgresql 2>/dev/null; then
        systemctl disable postgresql >> "$CLEANUP_LOG" 2>&1 || true
        log "PostgreSQL service disabled"
    fi
    
    # Disable MongoDB
    if systemctl is-enabled --quiet mongod 2>/dev/null; then
        systemctl disable mongod >> "$CLEANUP_LOG" 2>&1 || true
        log "MongoDB service disabled"
    fi
    
    # Disable Nginx
    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        systemctl disable nginx >> "$CLEANUP_LOG" 2>&1 || true
        log "Nginx service disabled"
    fi
    
    log "All services disabled"
}

# Function to remove MySQL
remove_mysql() {
    log "Removing MySQL..."
    
    # Remove MySQL packages
    if dpkg -l | grep -q mysql-server; then
        apt-get remove --purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* >> "$CLEANUP_LOG" 2>&1 || true
        log "MySQL packages removed"
    fi
    
    # Remove MySQL configuration files
    rm -rf /etc/mysql >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/lib/mysql >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/log/mysql >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /usr/share/mysql >> "$CLEANUP_LOG" 2>&1 || true
    
    # Remove MySQL user and group
    if id mysql &>/dev/null; then
        userdel mysql >> "$CLEANUP_LOG" 2>&1 || true
        log "MySQL user removed"
    fi
    
    if getent group mysql &>/dev/null; then
        groupdel mysql >> "$CLEANUP_LOG" 2>&1 || true
        log "MySQL group removed"
    fi
    
    log "MySQL completely removed"
}

# Function to remove PostgreSQL
remove_postgresql() {
    log "Removing PostgreSQL..."
    
    # Remove PostgreSQL packages
    if dpkg -l | grep -q postgresql; then
        apt-get remove --purge -y postgresql postgresql-contrib postgresql-* >> "$CLEANUP_LOG" 2>&1 || true
        log "PostgreSQL packages removed"
    fi
    
    # Remove PostgreSQL configuration files
    rm -rf /etc/postgresql >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/lib/postgresql >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/log/postgresql >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /usr/share/postgresql >> "$CLEANUP_LOG" 2>&1 || true
    
    # Remove PostgreSQL user and group
    if id postgres &>/dev/null; then
        userdel postgres >> "$CLEANUP_LOG" 2>&1 || true
        log "PostgreSQL user removed"
    fi
    
    if getent group postgres &>/dev/null; then
        groupdel postgres >> "$CLEANUP_LOG" 2>&1 || true
        log "PostgreSQL group removed"
    fi
    
    log "PostgreSQL completely removed"
}

# Function to remove MongoDB
remove_mongodb() {
    log "Removing MongoDB..."
    
    # Remove MongoDB packages
    if dpkg -l | grep -q mongodb-org; then
        apt-get remove --purge -y mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools >> "$CLEANUP_LOG" 2>&1 || true
        log "MongoDB packages removed"
    fi
    
    # Remove MongoDB configuration files
    rm -rf /etc/mongod.conf >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/lib/mongodb >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/log/mongodb >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /usr/share/mongodb >> "$CLEANUP_LOG" 2>&1 || true
    
    # Remove MongoDB repository
    rm -f /etc/apt/sources.list.d/mongodb-org-*.list >> "$CLEANUP_LOG" 2>&1 || true
    rm -f /usr/share/keyrings/mongodb-server-*.gpg >> "$CLEANUP_LOG" 2>&1 || true
    
    # Remove MongoDB user and group
    if id mongodb &>/dev/null; then
        userdel mongodb >> "$CLEANUP_LOG" 2>&1 || true
        log "MongoDB user removed"
    fi
    
    if getent group mongodb &>/dev/null; then
        groupdel mongodb >> "$CLEANUP_LOG" 2>&1 || true
        log "MongoDB group removed"
    fi
    
    log "MongoDB completely removed"
}

# Function to remove Nginx and SSL certificates
remove_nginx() {
    log "Removing Nginx and SSL certificates..."
    
    # Remove SSL certificates
    if command -v certbot &> /dev/null; then
        certbot delete --cert-name mysql-*.mydbportal.com --non-interactive >> "$CLEANUP_LOG" 2>&1 || true
        certbot delete --cert-name postgres-*.mydbportal.com --non-interactive >> "$CLEANUP_LOG" 2>&1 || true
        certbot delete --cert-name mongo-*.mydbportal.com --non-interactive >> "$CLEANUP_LOG" 2>&1 || true
        certbot delete --cert-name agent-*.mydbportal.com --non-interactive >> "$CLEANUP_LOG" 2>&1 || true
        log "SSL certificates removed"
    fi
    
    # Remove Nginx packages
    if dpkg -l | grep -q nginx; then
        apt-get remove --purge -y nginx nginx-common nginx-core >> "$CLEANUP_LOG" 2>&1 || true
        log "Nginx packages removed"
    fi
    
    # Remove Nginx configuration files
    rm -rf /etc/nginx >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/www/html >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /var/log/nginx >> "$CLEANUP_LOG" 2>&1 || true
    rm -rf /usr/share/nginx >> "$CLEANUP_LOG" 2>&1 || true
    
    # Remove Nginx user and group
    if id www-data &>/dev/null; then
        # Don't remove www-data as it might be used by other services
        log_info "Keeping www-data user (used by other services)"
    fi
    
    log "Nginx completely removed"
}

# Function to remove database agent
remove_agent() {
    log "Removing database agent..."
    
    # Remove systemd service
    if [ -f /etc/systemd/system/database-agent.service ]; then
        rm -f /etc/systemd/system/database-agent.service >> "$CLEANUP_LOG" 2>&1 || true
        systemctl daemon-reload >> "$CLEANUP_LOG" 2>&1 || true
        log "Database agent service file removed"
    fi
    
    # Remove agent directory
    rm -rf /opt/database-agent >> "$CLEANUP_LOG" 2>&1 || true
    
    log "Database agent completely removed"
}

# Function to remove certbot
remove_certbot() {
    log "Removing certbot..."
    
    # Remove Let's Encrypt certificates directory
    rm -rf /etc/letsencrypt >> "$CLEANUP_LOG" 2>&1 || true
    
    # Remove certbot packages (optional - comment out if you want to keep certbot)
    # apt-get remove --purge -y certbot python3-certbot-nginx >> "$CLEANUP_LOG" 2>&1 || true
    
    log "Certbot certificates removed"
}

# Function to clean up files
cleanup_files() {
    log "Cleaning up files..."
    
    # Remove credentials file
    if [ -f "$CREDENTIALS_FILE" ]; then
        rm -f "$CREDENTIALS_FILE" >> "$CLEANUP_LOG" 2>&1 || true
        log "Credentials file removed"
    fi
    
    # Remove log files
    if [ -f "$INSTALL_LOG" ]; then
        rm -f "$INSTALL_LOG" >> "$CLEANUP_LOG" 2>&1 || true
        log "Install log file removed"
    fi
    
    if [ -f "$NGINX_LOG" ]; then
        rm -f "$NGINX_LOG" >> "$CLEANUP_LOG" 2>&1 || true
        log "Nginx log file removed"
    fi
    
    # Remove temporary files
    rm -f temp_credentials.txt >> "$CLEANUP_LOG" 2>&1 || true
    
    log "Files cleaned up"
}

# Function to clean up package cache
cleanup_packages() {
    log "Cleaning up package cache..."
    
    # Remove orphaned packages
    apt-get autoremove -y >> "$CLEANUP_LOG" 2>&1 || true
    
    # Clean package cache
    apt-get autoclean >> "$CLEANUP_LOG" 2>&1 || true
    
    # Update package list
    apt-get update >> "$CLEANUP_LOG" 2>&1 || true
    
    log "Package cache cleaned"
}

# Function to check ports
check_ports() {
    log "Checking if ports are freed..."
    
    # Check MySQL port
    if netstat -tlnp | grep -q ":3306"; then
        log_warning "Port 3306 (MySQL) is still in use"
    else
        log "Port 3306 (MySQL) is free"
    fi
    
    # Check PostgreSQL port
    if netstat -tlnp | grep -q ":5432"; then
        log_warning "Port 5432 (PostgreSQL) is still in use"
    else
        log "Port 5432 (PostgreSQL) is free"
    fi
    
    # Check MongoDB port
    if netstat -tlnp | grep -q ":27017"; then
        log_warning "Port 27017 (MongoDB) is still in use"
    else
        log "Port 27017 (MongoDB) is free"
    fi
    
    # Check Nginx ports
    if netstat -tlnp | grep -q ":80\|:443"; then
        log_warning "Port 80/443 (HTTP/HTTPS) is still in use"
    else
        log "Port 80/443 (HTTP/HTTPS) is free"
    fi
    
    # Check agent port
    if netstat -tlnp | grep -q ":$AGENT_PORT"; then
        log_warning "Port $AGENT_PORT (Agent) is still in use"
    else
        log "Port $AGENT_PORT (Agent) is free"
    fi
}

# Function to kill remaining processes
kill_remaining_processes() {
    log "Killing any remaining database processes..."
    
    # Kill MySQL processes
    pkill -f mysql >> "$CLEANUP_LOG" 2>&1 || true
    pkill -f mysqld >> "$CLEANUP_LOG" 2>&1 || true
    
    # Kill PostgreSQL processes
    pkill -f postgres >> "$CLEANUP_LOG" 2>&1 || true
    pkill -f postgresql >> "$CLEANUP_LOG" 2>&1 || true
    
    # Kill MongoDB processes
    pkill -f mongod >> "$CLEANUP_LOG" 2>&1 || true
    pkill -f mongo >> "$CLEANUP_LOG" 2>&1 || true
    
    # Kill Nginx processes
    pkill -f nginx >> "$CLEANUP_LOG" 2>&1 || true
    
    # Kill agent processes
    pkill -f "database-agent" >> "$CLEANUP_LOG" 2>&1 || true
    pkill -f "agent.py" >> "$CLEANUP_LOG" 2>&1 || true
    
    # Wait a moment for processes to terminate
    sleep 5
    
    log "Remaining processes killed"
}

# Main execution
main() {
    log "Starting database server cleanup..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Confirm cleanup
    confirm_cleanup
    
    # Stop services
    stop_services
    
    # Disable services
    disable_services
    
    # Kill remaining processes
    kill_remaining_processes
    
    # Remove components
    remove_agent
    remove_nginx
    remove_mysql
    remove_postgresql
    remove_mongodb
    remove_certbot
    
    # Clean up files
    cleanup_files
    
    # Clean up packages
    cleanup_packages
    
    # Check ports
    check_ports
    
    log "Database server cleanup completed successfully!"
    log "Cleanup log saved to: $CLEANUP_LOG"
    
    echo ""
    echo "Cleanup Summary:"
    echo "================"
    echo "✓ MySQL removed completely"
    echo "✓ PostgreSQL removed completely"
    echo "✓ MongoDB removed completely"
    echo "✓ Nginx removed completely"
    echo "✓ SSL certificates removed"
    echo "✓ Database agent removed"
    echo "✓ Configuration files removed"
    echo "✓ Log files removed"
    echo "✓ Credentials file removed"
    echo "✓ Package cache cleaned"
    echo ""
    echo "Your system is now clean and ready for fresh installation!"
    echo "Note: This cleanup log will remain at: $CLEANUP_LOG"
}

# Execute main function
main "$@"