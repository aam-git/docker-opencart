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
# - Database connection testing
# - Automated OpenCart installation
# - Security hardening
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
    [ -z "$MYSQL_ROOT_PASSWORD" ] && missing_vars+=("MYSQL_ROOT_PASSWORD")
    
    # Required OpenCart variables
    [ -z "$OPENCART_USERNAME" ] && missing_vars+=("OPENCART_USERNAME")
    [ -z "$OPENCART_PASSWORD" ] && missing_vars+=("OPENCART_PASSWORD") 
    [ -z "$OPENCART_EMAIL" ] && missing_vars+=("OPENCART_EMAIL")
    
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
    
    # Check MySQL root password strength
    if [ ${#MYSQL_ROOT_PASSWORD} -lt 8 ]; then
        log "ERROR" "MYSQL_ROOT_PASSWORD must be at least 8 characters long"
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
        if [ "$MYSQL_ROOT_PASSWORD" = "$weak" ] || [ "$OPENCART_PASSWORD" = "$weak" ]; then
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
    log "INFO" "Starting automated OpenCart installation..."

    # Attempt to import SQL using the mysql CLI (more reliable than naive PHP splitting)
    log "INFO" "Looking for SQL dump to import using mysql client..."
    sql_file=''
    if [ -f /var/www/html/install/opencart.sql ]; then
        sql_file='/var/www/html/install/opencart.sql'
    elif [ -f /var/www/html/install/database.sql ]; then
        sql_file='/var/www/html/install/database.sql'
    else
        globs=(/var/www/html/install/*.sql)
        if [ -f "${globs[0]}" ]; then
            sql_file="${globs[0]}"
        fi
    fi

    if [ -n "$sql_file" ] && [ -f "$sql_file" ]; then
        log "INFO" "Found SQL file: $sql_file"
        if command -v mysql >/dev/null 2>&1; then
            log "INFO" "Importing SQL file into database $DB_DATABASE using mysql CLI..."
            if mysql -h "$DB_HOSTNAME" -P "$DB_PORT" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" < "$sql_file"; then
                log "INFO" "SQL import completed successfully."
            else
                log "WARN" "mysql CLI reported errors during import. Check logs above for details."
            fi
        else
            log "WARN" "mysql client not found in container. Cannot import SQL file automatically."
        fi
    else
        log "INFO" "No SQL file found to import; proceeding and will attempt to create admin user if tables exist."
    fi

    # Create a small PHP finalizer to ensure admin user and basic settings
    log "INFO" "Preparing inline PHP finalizer to create admin user and finalize settings..."
    cat > /tmp/install_opencart.php << 'EOF'
<?php
// Minimal PHP finalizer: ensure admin user exists and update basic settings
set_time_limit(0);
error_reporting(E_ALL);
ini_set('display_errors', 1);

$db_config = [
    'host' => getenv('DB_HOSTNAME') ?: 'database',
    'port' => getenv('DB_PORT') ?: 3306,
    'database' => getenv('DB_DATABASE') ?: 'opencart',
    'username' => getenv('DB_USERNAME') ?: 'root',
    'password' => getenv('DB_PASSWORD') ?: '',
    'prefix' => 'oc_'
];

try {
    $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $db_config['host'], $db_config['port'], $db_config['database']);
    $pdo = new PDO($dsn, $db_config['username'], $db_config['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
} catch (PDOException $e) {
    echo "ERROR: Could not connect to database: " . $e->getMessage() . "\n";
    exit(1);
}

// Check if user table exists
try {
    $prefix = $db_config['prefix'];
    $stmt = $pdo->query("SHOW TABLES LIKE '{$prefix}user'");
    if ($stmt && $stmt->rowCount() > 0) {
        echo "User table exists. Ensuring admin user and settings...\n";
    } else {
        echo "No user table found. Database import may have failed; please check logs.\n";
        exit(0);
    }
} catch (PDOException $e) {
    echo "ERROR checking database tables: " . $e->getMessage() . "\n";
    exit(1);
}

// Create admin user if not exists
try {
    $stmt = $pdo->query("SELECT COUNT(*) as c FROM `{$prefix}user` LIMIT 1");
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($row && intval($row['c']) > 0) {
        echo "Admin user(s) exist, skipping creation.\n";
    } else {
        echo "Creating admin user...\n";
        $salt = substr(md5(uniqid('', true)), 0, 9);
        $password = getenv('OPENCART_PASSWORD') ?: 'admin';
        $password_hash = md5($salt . md5($password));
        $username = getenv('OPENCART_USERNAME') ?: 'admin';
        $email = getenv('OPENCART_EMAIL') ?: 'admin@example.com';
        $now = date('Y-m-d H:i:s');
        $pdo->exec("INSERT INTO `{$prefix}user` (`username`,`password`,`salt`,`firstname`,`lastname`,`email`,`status`,`date_added`,`user_group`) VALUES (" .
            $pdo->quote($username) . "," . $pdo->quote($password_hash) . "," . $pdo->quote($salt) . "," . $pdo->quote('Admin') . "," . $pdo->quote('User') . "," . $pdo->quote($email) . ",1," . $pdo->quote($now) . ",1)");
        echo "Admin user created.\n";
    }
} catch (PDOException $e) {
    echo "WARN: Could not create admin user: " . $e->getMessage() . "\n";
}

// Update config settings (site name and url)
try {
    $site_name = getenv('OPENCART_SITE_NAME') ?: 'OpenCart';
    $site_url = getenv('OPENCART_SITE_URL') ?: 'http://localhost';
    $pdo->exec("UPDATE `{$prefix}setting` SET `value` = " . $pdo->quote($site_name) . " WHERE `key` = 'config_name'");
    $pdo->exec("UPDATE `{$prefix}setting` SET `value` = " . $pdo->quote($site_url) . " WHERE `key` = 'config_url'");
} catch (Exception $e) {
    echo "WARN: Could not update settings: " . $e->getMessage() . "\n";
}

echo "OpenCart finalizer finished.\n";

EOF

    log "INFO" "Attempting to run inline PHP finalizer..."
    if php /tmp/install_opencart.php; then
        log "INFO" "OpenCart admin user and settings finalized."
    else
        log "WARN" "Inline PHP finalizer reported issues. See above for details."
    fi

    # Clean up
    rm -f /tmp/install_opencart.php || true

    # Remove install directory for security
    if [ -d "/var/www/html/install" ]; then
        echo -e "${YELLOW}Removing install directory for security...${NC}"
        rm -rf /var/www/html/install
    fi

    # Set proper permissions
    chown -R www-data:www-data /var/www/html

    log "INFO" "OpenCart installation finalization completed!"
}

# Function to check if OpenCart is already installed
is_opencart_installed() {
    log "INFO" "Checking if OpenCart is already installed..."
    
    # Check if config.php has been modified from default
    if [ -f "/var/www/html/config.php" ]; then
        # Check if config.php contains actual database configuration
        if grep -q "define('DB_HOSTNAME'" /var/www/html/config.php && \
           grep -q "define('DB_USERNAME'" /var/www/html/config.php && \
           ! grep -q "localhost" /var/www/html/config.php; then
            log "INFO" "OpenCart appears to be already installed"
            return 0  # Installed
        fi
    fi
    
    log "INFO" "OpenCart is not installed yet"
    return 1  # Not installed
}

# Function to install OpenCart automatically
install_opencart() {
    log "INFO" "Installing OpenCart automatically..."
    
    # Update config files with database settings
    log "INFO" "Updating configuration files with database settings..."
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
    
    # Run the automated installation
    run_automated_installation
    
    # Remove install directory for security
    if [ -d "/var/www/html/install" ]; then
        log "INFO" "Removing install directory for security..."
        rm -rf /var/www/html/install
    fi
    
    # Set proper permissions
    chown -R www-data:www-data /var/www/html
    
    log "INFO" "OpenCart installation completed successfully!"
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