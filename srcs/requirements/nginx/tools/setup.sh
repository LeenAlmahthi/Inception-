#!/bin/sh
set -eu

SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/inception.crt"
KEY_FILE="$SSL_DIR/inception.key"
DOMAIN="${DOMAIN_NAME:-localhost}"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=MA/ST=Casablanca/L=Casablanca/O=42/OU=Inception/CN=$DOMAIN"
fi

exec nginx -g 'daemon off;'
