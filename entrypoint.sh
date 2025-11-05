#!/bin/bash
# =============================================================================
# OpenCart Docker Container Entrypoint Script
# =============================================================================
# 
# This script handles automated OpenCart installation and configuration
# 
# Features:
# - Environment variable validation
# - Password security enforcement
# - Database readiness checking
# - Automated installation with error handling
# - Comprehensive logging
#
# Author: Aaron M <info@aamservices.uk>
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# Configuration and Constants
# =============================================================================

# ANSI color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script metadata
readonly SCRIPT_NAME="OpenCart Entrypoint"
readonly SCRIPT_VERSION="1.0.0"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[$timestamp] [INFO]  $message${NC}" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] [WARN]  $message${NC}" ;;
        "ERROR") echo -e "${RED}[$timestamp] [ERROR] $message${NC}" ;;
        "DEBUG") echo -e "${BLUE}[$timestamp] [DEBUG] $message${NC}" ;;
        *)       echo -e "[$timestamp] [$level] $message" ;;
    esac
}

# Initialize container
log "INFO" "$SCRIPT_NAME v$SCRIPT_VERSION starting..."

# =============================================================================
# Environment Configuration
# =============================================================================

# Set default values for optional environment variables
readonly DB_HOSTNAME="${DB_HOSTNAME:-database}"
readonly DB_PORT="${DB_PORT:-3306}"
readonly DB_DATABASE="${DB_DATABASE:-opencart}"
readonly DB_USERNAME="${DB_USERNAME:-root}"
readonly OPENCART_SITE_URL="${OPENCART_SITE_URL:-http://localhost}"
readonly OPENCART_SITE_NAME="${OPENCART_SITE_NAME:-My OpenCart Store}"

# Required environment variables (must be provided by user)
readonly REQUIRED_VARS=(
    "DB_PASSWORD"
    "OPENCART_USERNAME" 
    "OPENCART_PASSWORD"
    "OPENCART_EMAIL"
)

log "INFO" "Environment configuration loaded"
log "DEBUG" "Database: $DB_USERNAME@$DB_HOSTNAME:$DB_PORT/$DB_DATABASE"
log "DEBUG" "Site: $OPENCART_SITE_NAME at $OPENCART_SITE_URL"

# =============================================================================
# Validation Functions  
# =============================================================================

# Check if all required environment variables are set
check_env_vars() {
    log "INFO" "Validating required environment variables..."
    local missing_vars=()
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "ERROR" "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log "ERROR" "  - $var"
        done
        log "ERROR" "Please set these variables in your .env file or docker-compose.yml"
        log "INFO" "See .env.example for configuration template"
        exit 1
    fi
    
    log "INFO" "All required environment variables are set"
}

# Function to validate passwords are not using default/insecure values
validate_passwords() {
    echo -e "${YELLOW}Validating password security...${NC}"
    local insecure_passwords=(
        "please_change_this_password"
        "secure_password_here"
        "admin123"
        "password"
        "123456"
        "admin"
        "root"
        "opencart"
        ""
    )
    
    # Check DB_PASSWORD
    for insecure_pwd in "${insecure_passwords[@]}"; do
        if [ "$DB_PASSWORD" = "$insecure_pwd" ]; then
            echo -e "${RED}SECURITY ERROR: You are using an insecure database password: '$DB_PASSWORD'${NC}"
            echo -e "${RED}Please change DB_PASSWORD in your .env file to a secure password${NC}"
            echo -e "${YELLOW}Example: DB_PASSWORD=MySecurePassword123!${NC}"
            exit 1
        fi
    done
    
    # Check OPENCART_PASSWORD
    for insecure_pwd in "${insecure_passwords[@]}"; do
        if [ "$OPENCART_PASSWORD" = "$insecure_pwd" ]; then
            echo -e "${RED}SECURITY ERROR: You are using an insecure OpenCart admin password: '$OPENCART_PASSWORD'${NC}"
            echo -e "${RED}Please change OPENCART_PASSWORD in your .env file to a secure password${NC}"
            echo -e "${YELLOW}Example: OPENCART_PASSWORD=MyAdminPassword456!${NC}"
            exit 1
        fi
    done
    
    # Check minimum password length
    if [ ${#DB_PASSWORD} -lt 8 ]; then
        echo -e "${RED}SECURITY ERROR: Database password must be at least 8 characters long${NC}"
        exit 1
    fi
    
    if [ ${#OPENCART_PASSWORD} -lt 8 ]; then
        echo -e "${RED}SECURITY ERROR: OpenCart admin password must be at least 8 characters long${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Password security validation passed${NC}"
}

# Function to wait for database to be ready
wait_for_db() {
    echo -e "${YELLOW}Waiting for database to be ready...${NC}"
    
    while ! php -r "
        try {
            \$pdo = new PDO('mysql:host=$DB_HOSTNAME;port=$DB_PORT', '$DB_USERNAME', '$DB_PASSWORD');
            echo 'connected';
        } catch (Exception \$e) {
            exit(1);
        }
    " > /dev/null 2>&1; do
        echo -e "${YELLOW}Database not ready yet, waiting...${NC}"
        sleep 2
    done
    
    echo -e "${GREEN}Database is ready${NC}"
}

# Function to check if OpenCart is already installed
is_opencart_installed() {
    # Check if config.php has been modified from default
    if [ -f "/var/www/html/config.php" ]; then
        # Check if config.php contains actual database configuration
        if grep -q "define('DB_HOSTNAME'" /var/www/html/config.php && \
           grep -q "define('DB_USERNAME'" /var/www/html/config.php && \
           ! grep -q "localhost" /var/www/html/config.php; then
            return 0  # Installed
        fi
    fi
    return 1  # Not installed
}

# Function to install OpenCart automatically
install_opencart() {
    echo -e "${YELLOW}Installing OpenCart automatically...${NC}"
    
    # Update config files with database settings
    sed -i "s/define('DB_HOSTNAME', 'localhost');/define('DB_HOSTNAME', '$DB_HOSTNAME');/" /var/www/html/config.php
    sed -i "s/define('DB_USERNAME', '');/define('DB_USERNAME', '$DB_USERNAME');/" /var/www/html/config.php
    sed -i "s/define('DB_PASSWORD', '');/define('DB_PASSWORD', '$DB_PASSWORD');/" /var/www/html/config.php
    sed -i "s/define('DB_DATABASE', '');/define('DB_DATABASE', '$DB_DATABASE');/" /var/www/html/config.php
    sed -i "s/define('DB_PORT', '3306');/define('DB_PORT', '$DB_PORT');/" /var/www/html/config.php
    
    # Update admin config
    sed -i "s/define('DB_HOSTNAME', 'localhost');/define('DB_HOSTNAME', '$DB_HOSTNAME');/" /var/www/html/admin/config.php
    sed -i "s/define('DB_USERNAME', '');/define('DB_USERNAME', '$DB_USERNAME');/" /var/www/html/admin/config.php
    sed -i "s/define('DB_PASSWORD', '');/define('DB_PASSWORD', '$DB_PASSWORD');/" /var/www/html/admin/config.php
    sed -i "s/define('DB_DATABASE', '');/define('DB_DATABASE', '$DB_DATABASE');/" /var/www/html/admin/config.php
    sed -i "s/define('DB_PORT', '3306');/define('DB_PORT', '$DB_PORT');/" /var/www/html/admin/config.php
    
    # Create installation script
    cat > /tmp/install_opencart.php << EOF
<?php
// OpenCart installation script
set_time_limit(0);

// Include OpenCart installation class if it exists
if (file_exists('/var/www/html/install/model/install/install.php')) {
    require_once('/var/www/html/install/model/install/install.php');
}

// Database configuration
\$db_config = array(
    'hostname' => '$DB_HOSTNAME',
    'username' => '$DB_USERNAME', 
    'password' => '$DB_PASSWORD',
    'database' => '$DB_DATABASE',
    'port'     => '$DB_PORT',
    'prefix'   => 'oc_'
);

// Admin user configuration
\$admin_config = array(
    'username' => '$OPENCART_USERNAME',
    'password' => '$OPENCART_PASSWORD',
    'email'    => '$OPENCART_EMAIL',
    'firstname'=> 'Admin',
    'lastname' => 'User'
);

// Site configuration
\$site_config = array(
    'name' => '$OPENCART_SITE_NAME',
    'url'  => '$OPENCART_SITE_URL'
);

try {
    // Connect to database
    \$pdo = new PDO("mysql:host={\$db_config['hostname']};port={\$db_config['port']};dbname={\$db_config['database']}", \$db_config['username'], \$db_config['password']);
    \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // Check if tables already exist
    \$stmt = \$pdo->query("SHOW TABLES LIKE 'oc_user'");
    if (\$stmt->rowCount() > 0) {
        echo "OpenCart tables already exist, skipping database installation\n";
    } else {
        echo "Installing OpenCart database...\n";
        
        // Read and execute SQL file
        if (file_exists('/var/www/html/install/opencart.sql')) {
            \$sql = file_get_contents('/var/www/html/install/opencart.sql');
            // Replace table prefix
            \$sql = str_replace('oc_', \$db_config['prefix'], \$sql);
            \$pdo->exec(\$sql);
            echo "Database tables created successfully\n";
        } else {
            throw new Exception("OpenCart SQL file not found");
        }
    }
    
    // Check if admin user exists
    \$stmt = \$pdo->prepare("SELECT user_id FROM oc_user WHERE username = ?");
    \$stmt->execute([\$admin_config['username']]);
    
    if (\$stmt->rowCount() > 0) {
        echo "Admin user already exists\n";
    } else {
        // Create admin user
        \$password_hash = password_hash(\$admin_config['password'], PASSWORD_DEFAULT);
        \$stmt = \$pdo->prepare("INSERT INTO oc_user (user_group_id, username, password, firstname, lastname, email, status, date_added) VALUES (1, ?, ?, ?, ?, ?, 1, NOW())");
        \$stmt->execute([
            \$admin_config['username'],
            \$password_hash,
            \$admin_config['firstname'],
            \$admin_config['lastname'],
            \$admin_config['email']
        ]);
        echo "Admin user created successfully\n";
    }
    
    // Update store settings
    \$stmt = \$pdo->prepare("UPDATE oc_setting SET value = ? WHERE \`key\` = 'config_name'");
    \$stmt->execute([\$site_config['name']]);
    
    \$stmt = \$pdo->prepare("UPDATE oc_setting SET value = ? WHERE \`key\` = 'config_url'");
    \$stmt->execute([\$site_config['url'] . '/']);
    
    echo "OpenCart installation completed successfully!\n";
    
} catch (Exception \$e) {
    echo "Installation failed: " . \$e->getMessage() . "\n";
    exit(1);
}
?>
EOF

    # Run the installation script
    php /tmp/install_opencart.php
    
    # Clean up
    rm -f /tmp/install_opencart.php
    
    # Remove install directory for security
    if [ -d "/var/www/html/install" ]; then
        echo -e "${YELLOW}Removing install directory for security...${NC}"
        rm -rf /var/www/html/install
    fi
    
    # Set proper permissions
    chown -R www-data:www-data /var/www/html
    
    echo -e "${GREEN}OpenCart installation completed successfully!${NC}"
}

# Main execution
echo -e "${GREEN}Starting OpenCart container initialization...${NC}"

# Check environment variables
check_env_vars

# Validate password security
validate_passwords

# Wait for database
wait_for_db

# Check if OpenCart is installed
if is_opencart_installed; then
    echo -e "${GREEN}OpenCart is already installed, starting normally...${NC}"
else
    echo -e "${YELLOW}OpenCart not installed, running automatic installation...${NC}"
    install_opencart
fi

# Set final permissions
chown -R www-data:www-data /var/www/html

echo -e "${GREEN}Initialization complete! Starting Apache...${NC}"

# Execute the original command (start Apache)
exec "$@"