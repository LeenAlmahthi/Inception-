FROM debian:bookworm

# install Php fpm 
RUN apt-get update && \
    apt-get install -y \
        php-fpm \
        php-mysql \
        php-cli \
        php-curl \
        php-gd \
        php-mbstring \
        php-xml \
        php-zip \
        curl \
        mariadb-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html

# wordpress 
RUN curl -O https://wordpress.org/latest.tar.gz && \
    tar -xzf latest.tar.gz && \
    mv wordpress/* /var/www/html/ && \
    rm -rf wordpress latest.tar.gz

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/setup.sh /setup.sh
RUN chmod +x /setup.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/setup.sh"]