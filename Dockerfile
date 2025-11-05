# =============================================================================
# OpenCart 3.0.4.1 Docker Container
# =============================================================================
# 
# Production-ready OpenCart e-commerce platform with automated installation
# 
# Features:
# - PHP 8.3 with Apache 2.4
# - Automated OpenCart installation and configuration
# - Security-first design with password validation
# - Multi-stage optimization for smaller image size
# 
# Author: Aaron M <info@aamservices.uk>
# Repository: https://github.com/aam-git/docker-opencart
# =============================================================================

FROM php:8.4-apache

# Metadata labels following OCI specification
LABEL org.opencontainers.image.title="OpenCart Docker Container"
LABEL org.opencontainers.image.description="Production-ready OpenCart 3.0.4.1 with automated installation"
LABEL org.opencontainers.image.version="3.0.4.1"
LABEL org.opencontainers.image.authors="Aaron Moy <info@aamservices.uk>"
LABEL org.opencontainers.image.url="https://github.com/aam-git/docker-opencart"
LABEL org.opencontainers.image.source="https://github.com/aam-git/docker-opencart"
LABEL org.opencontainers.image.licenses="MIT"
LABEL maintainer="aaron <info@aamservices.uk>"

# =============================================================================
# System Configuration
# =============================================================================

# Enable required Apache modules for OpenCart
RUN a2enmod rewrite headers

# Install system dependencies
# Note: Combining RUN commands reduces Docker layers and image size
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        zip \
        libzip-dev \
        default-mysql-client \
        curl \
        unzip && \
    rm -rf /var/lib/apt/lists/*

# Install PHP extensions required by OpenCart
RUN set -xe && \
    # Install image processing libraries
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libpng-dev \
        libjpeg-dev \
        libwebp-dev && \
    rm -rf /var/lib/apt/lists/* && \
    # Configure and install PHP extensions
    docker-php-ext-configure gd --with-jpeg=/usr --with-webp=/usr && \
    docker-php-ext-install -j$(nproc) \
        gd \
        mysqli \
        pdo_mysql \
        zip

# =============================================================================
# OpenCart Installation
# =============================================================================

# Set working directory
WORKDIR /var/www/html

# OpenCart version and download configuration
ENV OPENCART_VER=3.0.4.1 \
    OPENCART_MD5=f1cd69918494928fd2f13c948be0ba55 \
    OPENCART_FILE=opencart.zip

ENV OPENCART_URL=https://github.com/opencart/opencart/releases/download/${OPENCART_VER}/${OPENCART_VER}.zip

# Download, verify, and install OpenCart
RUN set -xe && \
    # Download OpenCart with retry logic
    curl -sSL --retry 3 --retry-delay 5 "${OPENCART_URL}" -o "${OPENCART_FILE}" && \
    # Verify file integrity
    echo "${OPENCART_MD5}  ${OPENCART_FILE}" | md5sum -c && \
    # Extract OpenCart files
    unzip -q "${OPENCART_FILE}" 'upload/*' -d /var/www/html/ && \
    mv /var/www/html/upload/* /var/www/html/ && \
    rm -rf /var/www/html/upload/ && \
    # Prepare configuration files
    mv config-dist.php config.php && \
    mv admin/config-dist.php admin/config.php && \
    # Cleanup
    rm "${OPENCART_FILE}" && \
    # Set proper OpenCart permissions (production-ready security model)
    # Change ownership from /var/www upwards to handle volume mounts properly
    chown -R www-data:www-data /var/www && \
    # Set directory permissions (755 - readable/executable by all, writable by owner)
    find /var/www/html -type d -exec chmod 755 {} + && \
    # Set file permissions (644 - readable by all, writable by owner only)
    find /var/www/html -type f -exec chmod 644 {} + && \
    # Set special permissions for OpenCart writable directories
    chmod 775 /var/www/html/image && \
    chmod 775 /var/www/html/system/storage && \
    # Create storage directory where OpenCart expects it (both locations for compatibility)
    mkdir -p /var/www/storage/{cache,logs,download,upload,session,modification} && \
    mkdir -p /var/www/html/system/storage/{cache,logs,download,upload,session,modification} && \
    # Set proper permissions for both storage locations
    chmod -R 775 /var/www/storage && \
    chmod -R 775 /var/www/html/system/storage && \
    chown -R www-data:www-data /var/www/storage

# =============================================================================
# Container Configuration
# =============================================================================

# Copy and configure entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Health check to ensure container is ready
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Expose standard HTTP and HTTPS ports
EXPOSE 80 443

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
