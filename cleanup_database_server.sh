#!/bin/bash

# Database Server Cleanup Script
# This script removes MySQL, PostgreSQL, MongoDB, and the database agent.
# It is designed to reverse the actions of the accompanying install script.
# WARNING: This will permanently delete all databases, users, and configurations!

set -e  # Exit on any error

# Configuration
CREDENTIALS_FILE="credentials"
INSTALL_LOG="install.log"
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
    echo "  - The database agent service"
    echo "  - All log files and credentials from the installation"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'YES' to confirm): " -r
    if [[ ! $REPLY == "YES" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_warning "User confirmed cleanup - proceeding with removal."
}

# Function to stop services
stop_services() {
    log "Stopping all relevant services..."
    
    # Stop database agent
    if systemctl is-active --quiet database-agent; then
        systemctl stop database-agent >> "$CLEANUP_LOG" 2>&1 || true
        log "Database agent service stopped."
    fi
    
    # Stop MySQL
    if systemctl is-active --quiet mysql; then
        systemctl stop mysql >> "$CLEANUP_LOG" 2>&1 || true
        log "MySQL service stopped."
    fi
    
    # Stop PostgreSQL
    if systemctl is-active --quiet postgresql; then
        systemctl stop postgresql >> "$CLEANUP_LOG" 2>&1 || true
        log "PostgreSQL service stopped."
    fi
    
    # Stop MongoDB
    if systemctl is-active --quiet mongod; then
        systemctl stop mongod >> "$CLEANUP_LOG" 2>&1 || true
        log "MongoDB service stopped."
    fi
    
    log "All services stopped."
}

# Function to disable services
disable_services() {
    log "Disabling all relevant services..."
    
    # Disable database agent
    if systemctl is-enabled --quiet database-agent; then
        systemctl disable database-agent >> "$CLEANUP_LOG" 2>&1 || true
        log "Database agent service disabled."
    fi
    
    # Disable MySQL
    if systemctl is-enabled --quiet mysql; then
        systemctl disable mysql >> "$CLEANUP_LOG" 2>&1 || true
        log "MySQL service disabled."
    fi
    
    # Disable PostgreSQL
    if systemctl is-enabled --quiet postgresql; then
        systemctl disable postgresql >> "$CLEANUP_LOG" 2>&1 || true
        log "PostgreSQL service disabled."
    fi
    
    # Disable MongoDB
    if systemctl is-enabled --quiet mongod; then
        systemctl disable mongod >> "$CLEANUP_LOG" 2>&1 || true
        log "MongoDB service disabled."
    fi
    
    log "All services disabled."
}

# Function to remove MySQL
remove_mysql() {
    log "Removing MySQL..."
    
    if dpkg -l | grep -q "mysql-server"; then
        apt-get remove --purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* >> "$CLEANUP_LOG" 2>&1
        log "MySQL packages purged."
    else
        log "MySQL not found, skipping removal."
        return
    fi
    
    rm -rf /etc/mysql /var/lib/mysql /var/log/mysql >> "$CLEANUP_LOG" 2>&1 || true
    log "MySQL directories removed."
    log "MySQL completely removed."
}

# Function to remove PostgreSQL
remove_postgresql() {
    log "Removing PostgreSQL..."
    
    if dpkg -l | grep -q "postgresql"; then
        apt-get remove --purge -y postgresql-* >> "$CLEANUP_LOG" 2>&1
        log "PostgreSQL packages purged."
    else
        log "PostgreSQL not found, skipping removal."
        return
    fi
    
    rm -rf /etc/postgresql /var/lib/postgresql /var/log/postgresql >> "$CLEANUP_LOG" 2>&1 || true
    log "PostgreSQL directories removed."
    log "PostgreSQL completely removed."
}

# Function to remove MongoDB
remove_mongodb() {
    log "Removing MongoDB..."
    
    if dpkg -l | grep -q "mongodb-org"; then
        apt-get remove --purge -y mongodb-org* >> "$CLEANUP_LOG" 2>&1
        log "MongoDB packages purged."
    else
        log "MongoDB not found, skipping removal."
        return
    fi
    
    rm -rf /var/log/mongodb /var/lib/mongodb >> "$CLEANUP_LOG" 2>&1 || true
    rm -f /etc/apt/sources.list.d/mongodb-org-*.list >> "$CLEANUP_LOG" 2>&1 || true
    rm -f /usr/share/keyrings/mongodb-server-*.gpg >> "$CLEANUP_LOG" 2>&1 || true
    log "MongoDB directories and repository files removed."
    log "MongoDB completely removed."
}

# Function to remove database agent
remove_agent() {
    log "Removing database agent..."
    
    if [ -f /etc/systemd/system/database-agent.service ]; then
        rm -f /etc/systemd/system/database-agent.service >> "$CLEANUP_LOG" 2>&1
        systemctl daemon-reload >> "$CLEANUP_LOG" 2>&1
        log "Database agent service file removed."
    fi
    
    rm -rf /opt/database-agent >> "$CLEANUP_LOG" 2>&1 || true
    log "Database agent directory removed."
    log "Database agent completely removed."
}

# Function to clean up files
cleanup_files() {
    log "Cleaning up log and credential files..."
    
    rm -f "$CREDENTIALS_FILE" "$INSTALL_LOG" temp_credentials.txt >> "$CLEANUP_LOG" 2>&1 || true
    
    log "Local files cleaned up."
}

# Function to clean up package cache
cleanup_packages() {
    log "Cleaning up package cache and orphaned packages..."
    
    apt-get autoremove -y >> "$CLEANUP_LOG" 2>&1
    apt-get autoclean >> "$CLEANUP_LOG" 2>&1
    apt-get update -y >> "$CLEANUP_LOG" 2>&1
    
    log "Package cache cleaned."
}

# Main execution
main() {
    log "Starting database server cleanup..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root."
        exit 1
    fi
    
    # Confirm cleanup with user
    confirm_cleanup
    
    # *** THIS IS THE FIX FOR THE HANGING ISSUE ***
    # Prevents apt-get from asking interactive questions
    export DEBIAN_FRONTEND=noninteractive
    
    # Gracefully stop and disable services first
    stop_services
    disable_services
    
    # Remove all installed components
    remove_agent
    remove_mysql
    remove_postgresql
    remove_mongodb
    
    # Final system cleanup
    cleanup_files
    cleanup_packages
    
    log "Database server cleanup completed successfully!"
    log "This cleanup log is located at: $CLEANUP_LOG"
    
    echo ""
    echo -e "${GREEN}Cleanup Summary:${NC}"
    echo "================="
    echo "✓ MySQL removed completely"
    echo "✓ PostgreSQL removed completely"
    echo "✓ MongoDB removed completely"
    echo "✓ Database agent removed"
    echo "✓ Configuration and log files removed"
    echo "✓ Package cache cleaned"
    echo ""
    echo -e "${YELLOW}Your system has been cleaned of the database server components.${NC}"
    echo "Note: The cleanup log remains at: $CLEANUP_LOG"
}

# Execute main function
main "$@"