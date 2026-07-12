# MariaDB container analysis (42 Inception — Mandatory only)

## Scope
This documentation analyzes only the MariaDB service for the Mandatory part of the Inception subject.

---

## 1) Purpose of MariaDB in Inception

MariaDB is the database backend storing WordPress data (posts, users, settings).
It runs in its own container and exposes no public port; WordPress connects to it via the internal Docker network.

---

## 2) Request/communication flow (summary)

Browser
→ NGINX (TLS termination)
→ WordPress (PHP-FPM handles dynamic requests)
→ MariaDB (SQL storage)

---

## 3) Files read

Location: `srcs/requirements/mariadb/`
- `Dockerfile` — builds MariaDB image.
- `conf/50-server.cnf` — minimal server configuration.
- `tools/setup.sh` — initialization and entrypoint script.
- `.env` (in `srcs/`) — provides `MYSQL_*` environment variables.

---

## 4) Line-by-line explanation — Dockerfile

File: `srcs/requirements/mariadb/Dockerfile`

1. `FROM debian:bookworm`
   - Base image: Debian Bookworm. Allowed by subject (Debian/Alpine permitted).

3-5. `RUN apt-get update && apt-get install -y --no-install-recommends mariadb-server mariadb-client && rm -rf /var/lib/apt/lists/*`
   - Installs MariaDB server and client packages.
   - `--no-install-recommends` keeps image smaller.
   - Clean apt lists to reduce final image size.

7. `COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf`
   - Copies custom server configuration into the official MariaDB config directory.

8. `COPY tools/setup.sh /setup.sh`
   - Copies the entrypoint/setup script that will initialize DB, create users and database.

9. `RUN chmod +x /setup.sh`
   - Makes script executable.

11. `EXPOSE 3306`
   - Declares internal DB port for documentation; Compose does not publish it to host.

13. `ENTRYPOINT ["/setup.sh"]`
   - Entrypoint runs setup script which starts/initializes MariaDB and finally `exec`s the server.

---

## 5) Line-by-line explanation — conf/50-server.cnf

1. `[mysqld]`
   - Section header for server options.
2. `bind-address = 0.0.0.0`
   - Accept connections from any interface inside the container (Docker network). Does not expose host.
3. `character-set-server = utf8mb4`
   - Use utf8mb4 as default character set for full Unicode support.
4. `collation-server = utf8mb4_unicode_ci`
   - Collation matching character set for correct sorting/comparison behaviour.

These settings are minimal and safe for WordPress operation.

---

## 6) Line-by-line explanation — tools/setup.sh

File: `srcs/requirements/mariadb/tools/setup.sh`

1. `#!/bin/sh`
   - POSIX shell interpreter.
2. `set -eu`
   - `-e`: exit on command error; `-u`: treat unset variables as error.

4-5. `DATA_DIR` and `SOCKET` variables
   - `DATA_DIR` is where MariaDB stores data (`/var/lib/mysql`).
   - `SOCKET` is the Unix socket used for local connections.

7-10. Mandatory environment variable checks
   - `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` are read from environment.
   - Script exits with error if any are missing (`${VAR:?message}`).

12. `mkdir -p /run/mysqld`
   - Ensure runtime socket directory exists.
13. `chown -R mysql:mysql /run/mysqld "$DATA_DIR"`
   - Ensure `mysql` user owns necessary directories.

15-18. Initialize DB system tables if missing
   - If `$DATA_DIR/mysql` missing, runs `mariadb-install-db --force` to create system tables.
   - `--force` helps avoid partial initialization issues.

20. Remove stale InnoDB log files
   - `rm -f "$DATA_DIR"/ib_logfile*` prevents InnoDB mismatches when reinitializing.

23. Start temporary server in background
   - `mariadbd --user=mysql --datadir=... --socket=... --skip-networking &`
   - Starts server without networking so SQL init can run safely.

26-28. Wait for server socket readiness
   - Loop until `mariadb-admin --socket=... ping` succeeds.

30-36. SQL initialization
   - Connects via socket as root (no password at initial state) and executes:
     - `ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';`
       - Sets root password as provided by env var.
     - `CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;`
       - Creates the WordPress database if not present.
     - `CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';`
       - Creates application user accessible from any host in Docker network.
     - `GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';`
       - Grants privileges to the app user on the WordPress DB.
     - `FLUSH PRIVILEGES;`
       - Applies changes.

38. Shutdown temporary server
   - `mariadb-admin --socket=... -uroot -p"$MYSQL_ROOT_PASSWORD" shutdown`
   - Shutdown cleanly after initialization.

39. `wait "$server_pid" || true`
   - Wait for background server to exit.

41. `exec mariadbd --user=mysql --datadir=... --socket=... --bind-address=0.0.0.0`
   - Replace shell with final server process as PID 1 and allow connections from other containers.

---

## 7) Environment variables

Defined in `srcs/.env`:
- `MYSQL_DATABASE=wordpress`
- `MYSQL_USER=leen`
- `MYSQL_PASSWORD=leen2004`
- `MYSQL_ROOT_PASSWORD=root2004`

Notes:
- Environment variables are used (mandatory).
- No secret is stored in Dockerfile (mandatory).
- For real evaluation, ensure `.env` is not committed with secret credentials. Using Docker secrets is recommended but optional.

---

## 8) Persistence and volumes

- Persistence provided by `srcs/docker-compose.yml` `volumes:` entry `mariadb_data` which maps to host path `/home/${USER}/data/mariadb` via driver options.
- This keeps MariaDB data across container recreation and satisfies requirement that data be stored under `/home/login/data` on host.

---

## 9) How WordPress connects to MariaDB

- WordPress reads DB connection variables (hostname `mariadb` or service name `mariadb`, user, password, database) from environment or WP config.
- In this project, the WordPress container should be configured to connect to hostname `mariadb` on port `3306` using the credentials provided in `.env`.
- Both containers share the compose network so DNS resolution by service name works.

---

## 10) Mandatory checklist for MariaDB service

### ✅ Correct implementations
- MariaDB runs in its own container (separate service). ✅
- Initialization script sets root password, creates DB and application user. ✅
- Uses environment variables from `.env`. ✅
- Entrypoint runs server as PID 1 (exec mariadbd). ✅
- Data persisted in named volume mapped to `/home/<user>/data/...`. ✅

### ⚠ Possible problems
- Host filesystems with limited feature support (or pre-existing partial initialization) may cause InnoDB errors; script attempts to mitigate by `--force` and removing stale ib_logfile*. ⚠
- `.env` currently contains plaintext passwords; subject recommends Docker secrets (optional). ⚠

### ❌ Missing requirements
- None at MariaDB service level after the applied minimal fixes.

---

## 11) What changed (summary)

- Added a complete `Dockerfile`, `conf/50-server.cnf`, and robust `setup.sh` to initialize MariaDB safely.
- The setup script now forces fresh system-table installation when needed and cleans stale InnoDB logs.
- No bonus features were added; minimal changes preserve architecture.

---

## 12) How to test MariaDB container

1. Ensure host data dirs exist (subject requires data under /home/<login>/data):
   - `mkdir -p /home/<login>/data/mariadb /home/<login>/data/wordpress`
2. Build and start MariaDB only:
   - `cd repo/srcs`
   - `docker compose build mariadb`
   - `docker compose up -d mariadb`
3. Verify container status and logs:
   - `docker compose ps`
   - `docker compose logs mariadb --tail=100`
4. Check DB contents and users:
   - `docker compose exec mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"`
   - `docker compose exec mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User,Host FROM mysql.user;"`
5. Verify WordPress can connect once WordPress container is started.

---

## 13) Common 42 evaluation questions (MariaDB) and short answers

Q: Where is the DB data stored on the host?
A: In `/home/<login>/data/mariadb` via named volume configuration.

Q: Are passwords in Dockerfiles?
A: No. Credentials are provided via `.env` (Make sure `.env` is not publicly committed).

Q: How do you ensure data persists across container restarts?
A: Using Docker named volumes mapped to host path under `/home/<login>/data`.

Q: How is the DB initialized?
A: `setup.sh` runs `mariadb-install-db` (if needed), starts a temporary server, runs SQL to set root password and create the WordPress DB and user, then restarts the server normally.

---

## 14) Notes and recommendations

- If InnoDB initialization errors persist on your environment, remove the host data directory and retry (this will destroy any stored data):
  - `docker compose down --volumes` then remove `/home/<login>/data/mariadb/*` and `docker compose up -d mariadb`.
- For secure production-like setup, use Docker secrets for DB passwords instead of plaintext `.env` file.

---

End of document.
