# Imagens de produção (dev continua em docker/php/Dockerfile).
#   docker build -f docker/prod/Dockerfile --target php .
#   docker build -f docker/prod/Dockerfile --target nginx .

FROM php:8.4-fpm AS php

WORKDIR /var/www

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpng-dev libjpeg62-turbo-dev libfreetype6-dev libzip-dev libonig-dev \
        libpq-dev libssl-dev pkg-config unzip git \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_pgsql zip mbstring exif gd opcache \
    && pecl install mongodb-1.21.10 \
    && docker-php-ext-enable mongodb \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/prod/php.ini /usr/local/etc/php/conf.d/zz-prod.ini
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

ENV APP_ENV=prod APP_DEBUG=0

# Dependências antes do código, para o cache de camada sobreviver a mudanças no src.
COPY composer.json composer.lock symfony.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --no-interaction --prefer-dist

COPY . .

# .env só com defaults não secretos; as variáveis reais do container vencem.
# cache:warmup antes do asset-map:compile: o warmup cria var/translations (ux-translator),
# que o asset mapper exige.
RUN cp .env.example .env \
    && composer dump-autoload --optimize --no-dev \
    && php bin/console importmap:install \
    && php bin/console doctrine:mongodb:generate:proxies \
    && php bin/console doctrine:mongodb:generate:hydrators \
    && php bin/console cache:warmup \
    && php bin/console asset-map:compile \
    && mkdir -p assets/uploads storage \
    && chown -R www-data:www-data var assets/uploads storage

USER www-data


FROM nginx:1.27-alpine AS nginx

COPY --from=php /var/www/public /var/www/public
COPY docker/prod/nginx.conf /etc/nginx/conf.d/default.conf
