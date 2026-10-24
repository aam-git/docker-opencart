#!/bin/bash
# OpenCart 3.0.5.1 entrypoint.
# Existing shops keep config.php, images, and storage. The database is upgraded once.

set -eo pipefail

HTML=/var/www/html
SRC=/usr/src/opencart
MAINT=/usr/local/bin/opencart-maint.php
SOURCE_VERSION_FILE="${HTML}/.docker-source-version"
TARGET_VERSION=3.0.5.1

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] %s: %s\n' "$timestamp" "$level" "$message"
}

apply_php_ini() {
    local memory="${PHP_MEMORY_LIMIT:-256M}"
    local execution="${PHP_MAX_EXECUTION_TIME:-300}"
    local upload="${PHP_UPLOAD_MAX_FILESIZE:-64M}"
    local post="${PHP_POST_MAX_SIZE:-64M}"
    local timezone="${TZ:-UTC}"
    local value

    for value in "$memory" "$execution" "$upload" "$post" "$timezone"; do
        if [[ ! "$value" =~ ^[A-Za-z0-9:._/+-]+$ ]]; then
            log "ERROR" "Refusing PHP setting that contains unsupported characters: ${value}"
            exit 1
        fi
    done

    cat > /usr/local/etc/php/conf.d/opencart.ini <<EOF
memory_limit = ${memory}
max_execution_time = ${execution}
upload_max_filesize = ${upload}
post_max_size = ${post}
date.timezone = ${timezone}
log_errors = On
error_log = /dev/stderr
opcache.enable = 1
opcache.enable_cli = 0
opcache.validate_timestamps = 1
opcache.revalidate_freq = 0
EOF
    log "INFO" "PHP memory_limit=${memory} max_execution_time=${execution}"
}

cli_env_ready() {
    [ -n "${DB_HOSTNAME:-}" ] \
        && [ -n "${DB_USERNAME:-}" ] \
        && [ -n "${DB_PASSWORD:-}" ] \
        && [ -n "${DB_DATABASE:-}" ] \
        && [ -n "${OPENCART_USERNAME:-}" ] \
        && [ -n "${OPENCART_PASSWORD:-}" ] \
        && [ -n "${OPENCART_EMAIL:-}" ]
}

validate_passwords() {
    local weak
    if [ "${#DB_PASSWORD}" -lt 8 ] || [ "${#OPENCART_PASSWORD}" -lt 8 ]; then
        log "ERROR" "DB_PASSWORD and OPENCART_PASSWORD must be at least 8 characters"
        exit 1
    fi
    for weak in password 123456 admin root test; do
        if [ "$DB_PASSWORD" = "$weak" ] || [ "$OPENCART_PASSWORD" = "$weak" ]; then
            log "ERROR" "Weak password detected. Choose a stronger password."
            exit 1
        fi
    done
}

wait_for_db() {
    local env_file="${1:-}"
    local attempt=0
    if [ -n "$env_file" ]; then
        # shellcheck disable=SC1090
        set -a
        source "$env_file"
        set +a
    fi
    log "INFO" "Waiting for database at ${DB_HOSTNAME:-mysql}:${DB_PORT:-3306}"
    while ! php "$MAINT" ping >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ $((attempt % 10)) -eq 0 ]; then
            log "INFO" "Database is not ready yet"
        fi
        sleep 2
    done
    log "INFO" "Database is ready"
}

remember_source_version() {
    local current=""
    if [ -f "$SOURCE_VERSION_FILE" ]; then
        return 0
    fi
    if [ -f "${HTML}/index.php" ]; then
        current=$(php "$MAINT" version || true)
    fi
    if [ -n "$current" ] && [ "$current" != "$TARGET_VERSION" ]; then
        printf '%s\n' "$current" > "$SOURCE_VERSION_FILE"
        log "INFO" "Existing OpenCart ${current} will be upgraded to ${TARGET_VERSION}"
    fi
}

source_version() {
    if [ -f "$SOURCE_VERSION_FILE" ]; then
        tr -d '[:space:]' < "$SOURCE_VERSION_FILE"
    fi
}

sync_tree() {
    local mode="$1"
    local -a excludes=(
        --exclude '/config.php'
        --exclude '/admin/config.php'
        --exclude '/.docker-source-version'
        --exclude '/.docker-pending-store-settings'
    )
    if [ "$mode" = "existing" ]; then
        excludes+=(--exclude '/image/' --exclude '/system/storage/')
    fi
    log "INFO" "Syncing OpenCart files (${mode})"
    rsync -a "${excludes[@]}" "${SRC}/" "${HTML}/"
    if [ ! -f "${HTML}/.htaccess" ] && [ -f "${HTML}/.htaccess.txt" ]; then
        cp "${HTML}/.htaccess.txt" "${HTML}/.htaccess"
    fi
    ensure_config_files
}

ensure_config_files() {
    if [ ! -f "${HTML}/config.php" ]; then
        if [ -s "${HTML}/config-dist.php" ]; then
            cp "${HTML}/config-dist.php" "${HTML}/config.php"
        else
            : > "${HTML}/config.php"
        fi
    fi
    if [ ! -f "${HTML}/admin/config.php" ]; then
        if [ -s "${HTML}/admin/config-dist.php" ]; then
            cp "${HTML}/admin/config-dist.php" "${HTML}/admin/config.php"
        else
            : > "${HTML}/admin/config.php"
        fi
    fi
}

sync_vendor() {
    local storage vendor_src
    vendor_src="${SRC}/system/storage/vendor/"
    if [ ! -d "$vendor_src" ]; then
        return 0
    fi
    storage=$(php "$MAINT" storage-path)
    mkdir -p "${storage}/vendor" "${storage}/cache" "${storage}/download" \
        "${storage}/logs" "${storage}/modification" "${storage}/session" \
        "${storage}/upload" "${storage}/backup"
    rsync -a --delete "$vendor_src" "${storage}/vendor/"
}

fix_ownership() {
    local storage
    storage=$(php "$MAINT" storage-path)
    log "INFO" "Setting ownership for the shop and storage"
    chown -R www-data:www-data "$HTML" "$storage"
    chmod 775 "$storage" "${HTML}/image" 2>/dev/null || true
}

store_configured() {
    [ -f "${HTML}/config.php" ] && php "$MAINT" configured
}

apply_store_identity() {
    local first_name last_name site_name
    first_name="${OPENCART_FIRSTNAME:-}"
    last_name="${OPENCART_LASTNAME:-}"
    site_name="${OPENCART_SITE_NAME:-}"
    if [ -z "$first_name" ] && [ -z "$last_name" ] && [ -z "$site_name" ]; then
        rm -f "${HTML}/.docker-pending-store-settings"
        return 0
    fi
    log "INFO" "Applying optional store name and admin name"
    php "$MAINT" apply-store "$first_name" "$last_name" "$site_name"
    rm -f "${HTML}/.docker-pending-store-settings"
}

run_cli_install() {
    local site_url
    site_url="${OPENCART_SITE_URL:-http://localhost}"
    site_url="${site_url%/}/"
    DB_PORT="${DB_PORT:-3306}"
    DB_DRIVER="${DB_DRIVER:-mysqli}"
    DB_PREFIX="${DB_PREFIX:-oc_}"
    # Set only when a new install supplied an optional name. A retry can finish
    # that step. Unset names keep the installer values.
    if [ -n "${OPENCART_FIRSTNAME:-}" ] || [ -n "${OPENCART_LASTNAME:-}" ] || [ -n "${OPENCART_SITE_NAME:-}" ]; then
        touch "${HTML}/.docker-pending-store-settings"
    fi
    log "INFO" "Running OpenCart CLI installation"
    (
        cd "$HTML"
        php install/cli_install.php install \
            --username "$OPENCART_USERNAME" \
            --email "$OPENCART_EMAIL" \
            --password "$OPENCART_PASSWORD" \
            --http_server "$site_url" \
            --db_driver "$DB_DRIVER" \
            --db_hostname "$DB_HOSTNAME" \
            --db_username "$DB_USERNAME" \
            --db_password "$DB_PASSWORD" \
            --db_database "$DB_DATABASE" \
            --db_port "$DB_PORT" \
            --db_prefix "$DB_PREFIX"
    )
    chmod 644 "${HTML}/config.php" "${HTML}/admin/config.php"
    apply_store_identity
    php "$MAINT" mark
    rm -rf "${HTML}/install"
    rm -f "$SOURCE_VERSION_FILE"
    log "INFO" "OpenCart CLI installation completed"
}

finish_existing_store() {
    local previous env_file
    previous=$(source_version || true)
    env_file=$(mktemp)
    chmod 600 "$env_file"
    if store_configured; then
        php "$MAINT" export "$env_file"
        # shellcheck disable=SC1090
        set -a
        source "$env_file"
        set +a
    fi
    wait_for_db
    if [ -n "$previous" ] && [ "$previous" != "$TARGET_VERSION" ]; then
        if ! php "$MAINT" upgrade-if-needed || ! php "$MAINT" current; then
            rm -f "$env_file"
            log "ERROR" "Upgrade failed. install/ has been left in place and config.php was not changed."
            exit 1
        fi
    elif ! php "$MAINT" mark; then
        rm -f "$env_file"
        log "ERROR" "Could not record the OpenCart version."
        exit 1
    fi
    rm -f "$env_file"
    if [ -f "${HTML}/.docker-pending-store-settings" ]; then
        apply_store_identity
    fi
    rm -rf "${HTML}/install"
    rm -f "$SOURCE_VERSION_FILE"
    chmod 644 "${HTML}/config.php" "${HTML}/admin/config.php" 2>/dev/null || true
    log "INFO" "Existing store is ready"
}

log "INFO" "Starting OpenCart ${TARGET_VERSION}"
apply_php_ini
remember_source_version

if store_configured || { cli_env_ready && php "$MAINT" tables; }; then
    sync_tree existing
    sync_vendor
    finish_existing_store
elif cli_env_ready; then
    validate_passwords
    sync_tree fresh
    sync_vendor
    chmod 666 "${HTML}/config.php" "${HTML}/admin/config.php"
    wait_for_db
    if php "$MAINT" tables; then
        log "INFO" "Database tables already exist. Skipping the CLI installer."
        finish_existing_store
    else
        run_cli_install
    fi
else
    log "INFO" "No install environment variables are set. Leaving the web installer available."
    sync_tree fresh
    sync_vendor
    chmod 666 "${HTML}/config.php" "${HTML}/admin/config.php"
fi

fix_ownership
log "INFO" "Starting Apache"
exec "$@"
