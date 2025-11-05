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

    echo -e "${GREEN}OpenCart installation finalization completed!${NC}"
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
    
    # Create installation script that doesn't rely on OpenCart classes
    cat > /tmp/install_opencart.php << EOF
<?php
// OpenCart installation script - Direct database approach
set_time_limit(0);

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
        echo "OpenCart tables already exist, skipping database installation\\n";
    } else {
        echo "Installing OpenCart database...\\n";
        
        // Find and execute SQL file
        \$sql_file = '';
        if (file_exists('/var/www/html/install/opencart.sql')) {
            \$sql_file = '/var/www/html/install/opencart.sql';
        } elseif (file_exists('/var/www/html/install/database.sql')) {
            \$sql_file = '/var/www/html/install/database.sql';
        } else {
            // Search for SQL files in install directory
            \$sql_files = glob('/var/www/html/install/*.sql');
            if (!empty(\$sql_files)) {
                \$sql_file = \$sql_files[0];
            }
        }
        
        if (\$sql_file && file_exists(\$sql_file)) {
            echo "Using SQL file: \$sql_file\\n";
            \$sql = file_get_contents(\$sql_file);
            
            // Split SQL into individual statements
            \$statements = array_filter(array_map('trim', explode(';', \$sql)));
            
            foreach (\$statements as \$statement) {
                if (!empty(\$statement)) {
                    try {
                        \$pdo->exec(\$statement);
                    } catch (Exception \$e) {
                        // Log but continue - some statements might fail due to existing data
                        echo "Warning: " . \$e->getMessage() . "\\n";
                    }
                }
            }
            echo "Database tables created successfully\\n";
        } else {
            echo "Warning: No SQL installation file found, attempting to continue...\\n";
        }
    }
    
    // Wait a moment for tables to be ready
    sleep(1);
    
    // Check if admin user table exists and create admin user
    try {
        \$stmt = \$pdo->query("DESCRIBE oc_user");
        if (\$stmt) {
            // Check if admin user exists
            \$stmt = \$pdo->prepare("SELECT user_id FROM oc_user WHERE username = ?");
            \$stmt->execute([\$admin_config['username']]);
            
            if (\$stmt->rowCount() > 0) {
                echo "Admin user already exists\\n";
            } else {
                // Create admin user - use MD5 for compatibility with older OpenCart versions
                \$password_hash = md5(\$admin_config['password']);
                \$stmt = \$pdo->prepare("INSERT INTO oc_user (user_group_id, username, password, firstname, lastname, email, status, date_added) VALUES (1, ?, ?, ?, ?, ?, 1, NOW())");
                \$stmt->execute([
                    \$admin_config['username'],
                    \$password_hash,
                    \$admin_config['firstname'],
                    \$admin_config['lastname'],
                    \$admin_config['email']
                ]);
                echo "Admin user created successfully\\n";
            }
        }
    } catch (Exception \$e) {
        echo "Warning: Could not create admin user - " . \$e->getMessage() . "\\n";
    }
    
    // Update store settings if settings table exists
    try {
        \$stmt = \$pdo->query("DESCRIBE oc_setting");
        if (\$stmt) {
            \$stmt = \$pdo->prepare("UPDATE oc_setting SET value = ? WHERE \\\`key\\\` = 'config_name'");
            \$stmt->execute([\$site_config['name']]);
            
            \$stmt = \$pdo->prepare("UPDATE oc_setting SET value = ? WHERE \\\`key\\\` = 'config_url'");
            \$stmt->execute([\$site_config['url'] . '/']);
            
            echo "Store settings updated successfully\\n";
        }
    } catch (Exception \$e) {
        echo "Warning: Could not update store settings - " . \$e->getMessage() . "\\n";
    }
    
    echo "OpenCart installation completed successfully!\\n";
    
} catch (Exception \$e) {
    echo "Installation failed: " . \$e->getMessage() . "\\n";
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