# =============================================================================
# OpenCart 3.0.5.1 Docker Container
# =============================================================================
#
# PHP 8.4 with Apache. Existing 3.0.3.x stores mounted at /var/www are
# upgraded in place. New stores can be installed from the CLI or the web installer.
#
# Author: Aaron M <info@aamservices.uk>
# Repository: https://github.com/aam-git/docker-opencart
# =============================================================================

FROM php:8.4-apache

LABEL org.opencontainers.image.title="OpenCart Docker Container"
LABEL org.opencontainers.image.description="OpenCart 3.0.5.1 on PHP 8.4, compatible with existing 3.0.3.x volumes"
LABEL org.opencontainers.image.version="3.0.5.1"
LABEL org.opencontainers.image.authors="Aaron Moy <info@aamservices.uk>"
LABEL org.opencontainers.image.url="https://github.com/aam-git/docker-opencart"
LABEL org.opencontainers.image.source="https://github.com/aam-git/docker-opencart"
LABEL org.opencontainers.image.licenses="MIT"
LABEL maintainer="aaron <info@aamservices.uk>"

# mbstring on PHP 8.4 needs Oniguruma headers. The official image does not ship them.
# Extensions are installed one at a time. A parallel install can delete modules/ mid-copy.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        default-mysql-client \
        libjpeg-dev \
        libonig-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        rsync \
        unzip; \
    docker-php-ext-configure gd --with-jpeg --with-webp; \
    docker-php-ext-install gd; \
    docker-php-ext-install mbstring; \
    docker-php-ext-install mysqli; \
    docker-php-ext-install pdo_mysql; \
    docker-php-ext-install zip; \
    a2enmod rewrite headers; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

ENV OPENCART_VER=3.0.5.1 \
    OPENCART_MD5=d7b8c2a9c7e2e020bfac233b0fb59fb6 \
    OPENCART_FILE=opencart.zip

ENV OPENCART_URL=https://github.com/opencart/opencart/releases/download/${OPENCART_VER}/opencart-${OPENCART_VER}.zip

# Keep a pristine tree outside /var/www. A volume mounted at /var/www hides
# the files baked into the image, so upgrades are copied from /usr/src/opencart.
RUN set -eux; \
    curl -fsSL --retry 3 --retry-delay 5 -o "/tmp/${OPENCART_FILE}" "${OPENCART_URL}"; \
    echo "${OPENCART_MD5}  /tmp/${OPENCART_FILE}" | md5sum -c; \
    mkdir -p /tmp/opencart-unpack /usr/src/opencart; \
    unzip -q "/tmp/${OPENCART_FILE}" 'upload/*' -d /tmp/opencart-unpack; \
    mv /tmp/opencart-unpack/upload/* /usr/src/opencart/; \
    rm -rf /tmp/opencart-unpack "/tmp/${OPENCART_FILE}"; \
    # 3.0.5.0+ tables are utf8mb4, but the drivers still connect as utf8.
    # https://github.com/opencart/opencart/issues/15695
    sed -i "s/set_charset('utf8')/set_charset('utf8mb4')/" /usr/src/opencart/system/library/db/mysqli.php; \
    sed -i \
        -e "s/SET NAMES 'utf8'/SET NAMES 'utf8mb4'/" \
        -e "s/SET CHARACTER SET utf8/SET CHARACTER SET utf8mb4/" \
        -e "s/CHARACTER_SET_CONNECTION=utf8/CHARACTER_SET_CONNECTION=utf8mb4/" \
        /usr/src/opencart/system/library/db/pdo.php; \
    # PHP 8 no longer passes errcontext into error handlers.
    sed -i 's/array \$errcontext)/array \$errcontext = [])/' /usr/src/opencart/install/cli_install.php; \
    # 1006 disables every modification. Leave the records as the shop set them.
    sed -i '/modification` SET status = 0/d' /usr/src/opencart/install/model/upgrade/1006.php; \
    php -r '$$path="/usr/src/opencart/system/framework.php"; $$source=file_get_contents($$path); $$needle="\tif (!(error_reporting() & \$$code)) {\n\t\treturn false;\n\t}\n"; $$block=$$needle."\n\tif (\$$code === E_DEPRECATED || \$$code === E_USER_DEPRECATED) {\n\t\t\$$log->write(\"PHP Deprecated: \" . \$$message . \" in \" . \$$file . \" on line \" . \$$line);\n\t\terror_log(\"PHP Deprecated: \" . \$$message . \" in \" . \$$file . \" on line \" . \$$line);\n\t\treturn true;\n\t}\n"; if ($$source===false || substr_count($$source, $$needle)!==1) { fwrite(STDERR, "framework.php error handler anchor was not found\n"); exit(1);} if (file_put_contents($$path, str_replace($$needle, $$block, $$source))===false) { fwrite(STDERR, "framework.php could not be updated\n"); exit(1);}'; \
    cp -a /usr/src/opencart/. /var/www/html/; \
    if [ -s /var/www/html/config-dist.php ]; then \
        cp /var/www/html/config-dist.php /var/www/html/config.php; \
    else \
        : > /var/www/html/config.php; \
    fi; \
    if [ -s /var/www/html/admin/config-dist.php ]; then \
        cp /var/www/html/admin/config-dist.php /var/www/html/admin/config.php; \
    else \
        : > /var/www/html/admin/config.php; \
    fi; \
    if [ ! -f /var/www/html/.htaccess ] && [ -f /var/www/html/.htaccess.txt ]; then \
        cp /var/www/html/.htaccess.txt /var/www/html/.htaccess; \
    fi; \
    chown -R www-data:www-data /var/www/html; \
    find /var/www/html -type d -exec chmod 755 {} +; \
    find /var/www/html -type f -exec chmod 644 {} +; \
    chmod 775 /var/www/html/image /var/www/html/system/storage; \
    chmod 666 /var/www/html/config.php /var/www/html/admin/config.php; \
    chmod -R a+rX /usr/src/opencart

COPY opencart-apache.conf /etc/apache2/conf-available/opencart.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY opencart-maint.php /usr/local/bin/opencart-maint.php
COPY aam-php8-repair.ocmod.xml /usr/local/share/opencart/aam-php8-repair.ocmod.xml

RUN a2enconf opencart && chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/opencart-maint.php

# No healthcheck. A maintenance 503 must not take the container out of the proxy.
HEALTHCHECK NONE

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]
