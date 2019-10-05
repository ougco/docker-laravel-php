ARG PHP_VERSION=7.3
FROM php:${PHP_VERSION}-fpm-alpine

ARG TZ=UTC
ARG DOCKER_APP_ROOT_PATH=/app

ENV COMPOSER_HOME /composer
ENV COMPOSER_ALLOW_SUPERUSER 1
ENV PATH ./vendor/bin:/composer/vendor/bin:$PATH
ENV DOCKER_APP_ROOT_PATH=$DOCKER_APP_ROOT_PATH

# Set the application directory and volume
WORKDIR $DOCKER_APP_ROOT_PATH
VOLUME $DOCKER_APP_ROOT_PATH

RUN set -xe && \
    \
    # Use the default production configuration and set the php_ini
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" && \
    \
    apk update && \
    \
    apk upgrade && \
    \
    # Install dev dependencies
    apk add --no-cache --update --virtual .build-deps \
        $PHPIZE_DEPS \
        curl-dev \
        cyrus-sasl-dev \
        libtool \
        libxml2-dev \
        openssl-dev \
        pcre-dev && \
    \
    # Install production dependencies
    apk add --no-cache --update \
        bash \
        curl \
        coreutils \
        git \
        file \
        findutils \
        cksfv \
        icu \
        icu-dev \
        libxslt-dev \
        libevent-dev \
        libintl \
        libmemcached-dev \
        libssh2-dev \
        libzip-dev \
        libbz2 \
        mysql-client \
        bzip2-dev \
        unrar \
        zip \
        zlib-dev && \
    \
    # Install and enable php extensions
    docker-php-ext-configure zip --with-libzip && \
    \
    docker-php-ext-install -j$(nproc) \
        bz2 \
        bcmath \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        soap \
        sockets \
        tokenizer \
        xsl \
        zip && \
    \
    echo '' | pecl install -f igbinary && \
    docker-php-ext-enable igbinary && \
    \
    yes | pecl install -f redis && \
    docker-php-ext-enable redis && \
    \
    # Load event extension at the last
    echo '' | pecl install -f event && \
    docker-php-ext-enable --ini-name zz-event.ini event && \
    \
    # Install memcached
    ( \
        pecl install --nobuild memcached && \
        cd "$(pecl config-get temp_dir)/memcached" && \
        docker-php-ext-configure "$(pecl config-get temp_dir)/memcached" \
        --enable-memcached-session --enable-memcached-igbinary --enable-memcached-json && \
        docker-php-ext-install "$(pecl config-get temp_dir)/memcached" \
    ) && \
    \
    # Install composer & global package to add parallel requests support.
    curl -sS https://getcomposer.org/installer | \
    php -- --install-dir=/usr/local/bin --filename=composer && \
    \
    composer global require hirak/prestissimo -n --prefer-source && \
    \
    # Cleanup: build deps and cache.
    apk del -f --purge --no-network .build-deps && \
    \
    rm -rf /tmp/* /var/cache/apk/* && \
    \
    composer clear-cache

# Copy PHP.ini settings to the container
COPY config/* $PHP_INI_DIR/conf.d/

# Set timezone & update app root path in crontab.
RUN sed -i "s|UTC|${TZ}|i" $PHP_INI_DIR/conf.d/05-date-timezone.ini
