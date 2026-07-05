# WordPress + CiviCRM PHP-FPM image for local development.
# Based on patterns from https://github.com/civicrm/civicrm-docker

ARG WORDPRESS_VERSION=
ARG CIVICRM_VERSION=6.0.3

FROM wordpress:php8.2-fpm AS build

ARG WORDPRESS_VERSION
ARG CIVICRM_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl less unzip \
    && curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

RUN if [ -n "${WORDPRESS_VERSION}" ]; then \
      php -d memory_limit=-1 /usr/local/bin/wp core download --allow-root --version="${WORDPRESS_VERSION}"; \
    else \
      php -d memory_limit=-1 /usr/local/bin/wp core download --allow-root; \
    fi \
    && mkdir -p wp-content/uploads wp-content/languages \
    && curl -fsSL "https://download.civicrm.org/civicrm-${CIVICRM_VERSION}-wordpress.zip" -o /tmp/civicrm.zip \
    && unzip /tmp/civicrm.zip -d wp-content/plugins \
    && rm /tmp/civicrm.zip

FROM wordpress:php8.2-fpm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        default-mysql-client \
        gosu \
        less \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libmagickwand-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" bcmath exif gd intl mysqli opcache pdo_mysql zip \
    && pecl install igbinary imagick \
    && docker-php-ext-enable igbinary imagick \
    && curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp \
    && curl -fsSL https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv \
    && chmod +x /usr/local/bin/cv \
    && printf "[client]\nssl=false\n" > /etc/mysql/conf.d/disable-ssl.cnf \
    && rm -rf /var/lib/apt/lists/*

RUN { \
        echo 'upload_max_filesize = 64M'; \
        echo 'post_max_size = 64M'; \
        echo 'memory_limit = 512M'; \
        echo 'max_execution_time = 300'; \
        echo 'max_input_vars = 3000'; \
    } > /usr/local/etc/php/conf.d/cocodems.ini

COPY --from=build --chown=www-data:www-data /var/www/html /usr/src/wordpress
COPY wp-config.php /usr/src/wordpress/wp-config.php
COPY cocodems-entrypoint.sh install-site.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/cocodems-entrypoint.sh /usr/local/bin/install-site.sh \
    && mkdir -p /var/www/private \
    && chown www-data:www-data /var/www/private

ENV CIVICRM_UF=WordPress \
    WORDPRESS_CONFIG_FILE=/var/www/private/wp-config.php

ENTRYPOINT ["cocodems-entrypoint.sh"]
CMD ["php-fpm"]
