#!/bin/sh
set -eu

WP_DIR=/var/www/html

DB_NAME="${MYSQL_DATABASE:-wordpress}"
DB_USER="${MYSQL_USER:-wp_user}"
DB_PASSWORD="${MYSQL_PASSWORD:-wp_pass}"
DB_HOST="${DB_HOST:-mariadb}"

# Create wp-config.php from sample if not present
if [ ! -f "$WP_DIR/wp-config.php" ]; then
    if [ -f "$WP_DIR/wp-config-sample.php" ]; then
        cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"
        sed -i "s/database_name_here/${DB_NAME}/" "$WP_DIR/wp-config.php"
        sed -i "s/username_here/${DB_USER}/" "$WP_DIR/wp-config.php"
        sed -i "s/password_here/${DB_PASSWORD}/" "$WP_DIR/wp-config.php"
        sed -i "s/localhost/${DB_HOST}/" "$WP_DIR/wp-config.php"

        # Generate authentication unique keys and salts
        if command -v curl >/dev/null 2>&1; then
            curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> "$WP_DIR/wp-config.php"
        else
            printf "\n" >> "$WP_DIR/wp-config.php"
            for i in 1 2 3 4 5 6 7 8; do
                key=$(head -c16 /dev/urandom | sha1sum | awk '{print $1}')
                echo "define('AUTH_KEY', '${key}');" >> "$WP_DIR/wp-config.php"
            done
        fi
    fi
fi

# Set permissions
chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;

# Start php-fpm in foreground (try specific binary then fallback)
if command -v php-fpm8.2 >/dev/null 2>&1; then
    exec php-fpm8.2 -F
else
    exec php-fpm -F
fi
