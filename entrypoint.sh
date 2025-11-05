#!/bin/bash
# =============================================================================
# OpenCart Docker Container Entrypoint Script
# =============================================================================
# 
# This script handles automated OpenCart installation and configuration
# 
# Features:
# - Environment variable validation with extensive configuration options
# - Password security enforcement
# - Database connection testing with configurable drivers and prefixes
# - Automated OpenCart installation (v3.x and v4.x compatible)
# - Multi-language support (v4.x)
# - Multi-store support via configurable table prefixes
# - Security hardening and proper permissions
# - Version auto-detection and parameter adaptation
#
# Supported Environment Variables:
# - Database: DB_HOSTNAME, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD, DB_DRIVER, DB_PREFIX
# - Admin User: OPENCART_USERNAME, OPENCART_PASSWORD, OPENCART_EMAIL, OPENCART_FIRSTNAME, OPENCART_LASTNAME
# - Site Config: OPENCART_SITE_NAME, OPENCART_SITE_URL, OPENCART_LANGUAGE
# - PHP Config: PHP_MAX_EXECUTION_TIME, PHP_MEMORY_LIMIT
#
# =============================================================================

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo -e "${RED}[$timestamp] ERROR: $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] WARN: $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}[$timestamp] INFO: $message${NC}"
            ;;
        *)
            echo -e "[$timestamp] $level: $message"
            ;;
    esac
}

# Function to check required environment variables
check_env_vars() {
    local missing_vars=()
    
    # Required database variables
    [ -z "$DB_HOSTNAME" ] && missing_vars+=("DB_HOSTNAME")
    [ -z "$DB_USERNAME" ] && missing_vars+=("DB_USERNAME") 
    [ -z "$DB_PASSWORD" ] && missing_vars+=("DB_PASSWORD")
    [ -z "$DB_DATABASE" ] && missing_vars+=("DB_DATABASE")
    
    # Required OpenCart variables
    [ -z "$OPENCART_USERNAME" ] && missing_vars+=("OPENCART_USERNAME")
    [ -z "$OPENCART_PASSWORD" ] && missing_vars+=("OPENCART_PASSWORD") 
    [ -z "$OPENCART_EMAIL" ] && missing_vars+=("OPENCART_EMAIL")
    
    # Set defaults for optional variables
    DB_DRIVER="${DB_DRIVER:-mysqli}"
    DB_PREFIX="${DB_PREFIX:-oc_}"
    OPENCART_LANGUAGE="${OPENCART_LANGUAGE:-en-gb}"
    OPENCART_FIRSTNAME="${OPENCART_FIRSTNAME:-Admin}"
    OPENCART_LASTNAME="${OPENCART_LASTNAME:-User}"
    
    log "INFO" "Using database driver: $DB_DRIVER"
    log "INFO" "Using database prefix: $DB_PREFIX"
    log "INFO" "Using OpenCart language: $OPENCART_LANGUAGE"
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        log "ERROR" "Please set all required variables before starting the container"
        exit 1
    fi
    
    log "INFO" "All required environment variables are set"
}

# Function to validate password security
validate_passwords() {
    log "INFO" "Validating password security requirements..."
    
    # Check database password strength
    if [ ${#DB_PASSWORD} -lt 8 ]; then
        log "ERROR" "DB_PASSWORD must be at least 8 characters long"
        exit 1
    fi
    
    # Check OpenCart admin password strength
    if [ ${#OPENCART_PASSWORD} -lt 8 ]; then
        log "ERROR" "OPENCART_PASSWORD must be at least 8 characters long"
        exit 1
    fi
    
    # Check for common weak passwords
    local weak_passwords=("password" "123456" "admin" "root" "test")
    for weak in "${weak_passwords[@]}"; do
        if [ "$DB_PASSWORD" = "$weak" ] || [ "$OPENCART_PASSWORD" = "$weak" ]; then
            log "ERROR" "Weak password detected. Please use a stronger password."
            exit 1
        fi
    done
    
    log "INFO" "Password security validation passed"
}

# Function to wait for database to be ready
wait_for_db() {
    log "INFO" "Waiting for database to be ready..."
    
    while ! php -r "
        try {
            new PDO('mysql:host=$DB_HOSTNAME;port=${DB_PORT:-3306}', '$DB_USERNAME', '$DB_PASSWORD');
            echo 'connected';
        } catch (Exception \$e) {
            exit(1);
        }
    " > /dev/null 2>&1; do
        log "INFO" "Database not ready yet, waiting..."
        sleep 2
    done
    
    log "INFO" "Database is ready"
}

# Function to run automated OpenCart installation
run_automated_installation() {
    log "INFO" "Starting automated OpenCart installation using OpenCart's CLI installer..."

    # Ensure config files exist (rename from dist versions)
    if [ ! -f "/var/www/html/config.php" ] && [ -f "/var/www/html/config-dist.php" ]; then
        log "INFO" "Creating config.php from config-dist.php"
        cp /var/www/html/config-dist.php /var/www/html/config.php
    fi
    
    if [ ! -f "/var/www/html/admin/config.php" ] && [ -f "/var/www/html/admin/config-dist.php" ]; then
        log "INFO" "Creating admin/config.php from admin/config-dist.php"
        cp /var/www/html/admin/config-dist.php /var/www/html/admin/config.php
    fi

    # Make config files writable for installation
    chmod 666 /var/www/html/config.php /var/www/html/admin/config.php

    # Use OpenCart's official CLI installer
    log "INFO" "Running OpenCart CLI installation..."
    if [ -f "/var/www/html/install/cli_install.php" ]; then
        cd /var/www/html
        
        # Detect OpenCart version by checking SQL file structure
        if [ -f "/var/www/html/install/opencart-${OPENCART_LANGUAGE}.sql" ] || [ -f "/var/www/html/install/opencart-en-gb.sql" ]; then
            # OpenCart v4+ with language-specific SQL files
            log "INFO" "Detected OpenCart v4+ - using language parameter: $OPENCART_LANGUAGE"
            php install/cli_install.php install \
                --username "$OPENCART_USERNAME" \
                --email "$OPENCART_EMAIL" \
                --password "$OPENCART_PASSWORD" \
                --http_server "$OPENCART_SITE_URL/" \
                --language "$OPENCART_LANGUAGE" \
                --db_driver "$DB_DRIVER" \
                --db_hostname "$DB_HOSTNAME" \
                --db_username "$DB_USERNAME" \
                --db_password "$DB_PASSWORD" \
                --db_database "$DB_DATABASE" \
                --db_port "$DB_PORT" \
                --db_prefix "$DB_PREFIX"
        elif [ -f "/var/www/html/install/opencart.sql" ]; then
            # OpenCart v3.x with single SQL file
            log "INFO" "Detected OpenCart v3.x - using legacy parameters"
            php install/cli_install.php install \
                --username "$OPENCART_USERNAME" \
                --email "$OPENCART_EMAIL" \
                --password "$OPENCART_PASSWORD" \
                --http_server "$OPENCART_SITE_URL/" \
                --db_driver "$DB_DRIVER" \
                --db_hostname "$DB_HOSTNAME" \
                --db_username "$DB_USERNAME" \
                --db_password "$DB_PASSWORD" \
                --db_database "$DB_DATABASE" \
                --db_port "$DB_PORT" \
                --db_prefix "$DB_PREFIX"
        else
            log "ERROR" "Could not find OpenCart SQL installation files"
            return 1
        fi
        
        if [ $? -eq 0 ]; then
            log "INFO" "OpenCart CLI installation completed successfully!"
        else
            log "ERROR" "OpenCart CLI installation failed!"
            return 1
        fi
    else
        log "ERROR" "OpenCart CLI installer not found at /var/www/html/install/cli_install.php"
        return 1
    fi

    log "INFO" "OpenCart installation finalization completed!"
}

# Function to check if OpenCart is already installed
is_opencart_installed() {
    log "INFO" "Checking if OpenCart is already installed..."
    
    # Check if config.php has been modified from default and install directory is gone
    if [ -f "/var/www/html/config.php" ] && [ ! -d "/var/www/html/install" ]; then
        # Check if config.php contains actual database configuration (not default values)
        if grep -q "define('DB_HOSTNAME'" /var/www/html/config.php && \
           grep -q "define('DB_USERNAME'" /var/www/html/config.php && \
           ! grep -q "DB_HOSTNAME', ''" /var/www/html/config.php && \
           ! grep -q "DB_USERNAME', ''" /var/www/html/config.php; then
            log "INFO" "OpenCart appears to be already installed (config exists and install dir removed)"
            return 0  # Installed
        fi
    fi
    
    # Also check if we can connect to database and find OpenCart tables
    local prefix="${DB_PREFIX:-oc_}"
    if php -r "
        try {
            \$pdo = new PDO('mysql:host=$DB_HOSTNAME;port=${DB_PORT:-3306};dbname=$DB_DATABASE', '$DB_USERNAME', '$DB_PASSWORD');
            \$stmt = \$pdo->query('SHOW TABLES LIKE \"${prefix}user\"');
            if (\$stmt && \$stmt->rowCount() > 0) {
                exit(0); // Tables exist
            }
            exit(1); // No tables
        } catch (Exception \$e) {
            exit(1); // Connection failed
        }
    " 2>/dev/null; then
        log "INFO" "OpenCart database tables found - installation appears complete"
        return 0  # Installed
    fi
    
    log "INFO" "OpenCart is not installed yet"
    return 1  # Not installed
}

# Function to install OpenCart automatically
install_opencart() {
    log "INFO" "Installing OpenCart automatically..."
    
    # Run the automated installation using OpenCart's CLI installer
    if run_automated_installation; then
        log "INFO" "OpenCart installation completed successfully!"
        
        # Remove install directory for security (CLI installer handles config file creation)
        if [ -d "/var/www/html/install" ]; then
            log "INFO" "Removing install directory for security..."
            rm -rf /var/www/html/install
        fi
        
        # Set proper permissions
        chown -R www-data:www-data /var/www/html
        
        # Make config files read-only after installation
        chmod 644 /var/www/html/config.php /var/www/html/admin/config.php 2>/dev/null || true
        
        log "INFO" "OpenCart installation and security hardening completed!"
    else
        log "ERROR" "OpenCart installation failed!"
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

log "INFO" "Starting OpenCart container initialization..."

# Check environment variables
check_env_vars

# Validate password security
validate_passwords

# Wait for database
wait_for_db

# Check if OpenCart is installed
if is_opencart_installed; then
    log "INFO" "OpenCart is already installed, starting normally..."
else
    log "INFO" "OpenCart not installed, running automatic installation..."
    install_opencart
fi

# Set final permissions
chown -R www-data:www-data /var/www/html

log "INFO" "Initialization complete! Starting Apache..."

# Execute the original command (start Apache)
exec "$@"