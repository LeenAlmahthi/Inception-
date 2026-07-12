#!/bin/sh
set -eu

DATA_DIR="/var/lib/mysql"
SOCKET="/run/mysqld/mysqld.sock"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:?missing MYSQL_ROOT_PASSWORD}"
MYSQL_DATABASE="${MYSQL_DATABASE:?missing MYSQL_DATABASE}"
MYSQL_USER="${MYSQL_USER:?missing MYSQL_USER}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:?missing MYSQL_PASSWORD}"

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld "$DATA_DIR"

if [ ! -d "$DATA_DIR/mysql" ]; then
    # Ensure a clean initialization of system tables; --force avoids partial failures
    mariadb-install-db --user=mysql --datadir="$DATA_DIR" --basedir=/usr --force
fi

# Remove stale InnoDB logfiles that can cause InnoDB plugin init errors
rm -f "$DATA_DIR"/ib_logfile* || true

# Start temporary server to apply initial SQL configuration
mariadbd --user=mysql --datadir="$DATA_DIR" --socket="$SOCKET" --skip-networking &
server_pid="$!"

until mariadb-admin --socket="$SOCKET" ping >/dev/null 2>&1; do
    sleep 1
done

mariadb --socket="$SOCKET" -uroot <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

mariadb-admin --socket="$SOCKET" -uroot -p"$MYSQL_ROOT_PASSWORD" shutdown
wait "$server_pid" || true

exec mariadbd --user=mysql --datadir="$DATA_DIR" --socket="$SOCKET" --bind-address=0.0.0.0