# WordPress + PHP-FPM container analysis (42 Inception — Mandatory only)

## Scope
This document analyzes the WordPress service only and explains how it satisfies the mandatory Inception subject requirements.

---

## 1) Purpose of the WordPress container

The WordPress container provides the PHP application code (WordPress core) and runs PHP-FPM to process PHP requests. It does not act as a webserver — NGINX is the public HTTPS entrypoint and forwards PHP requests to PHP-FPM running in this container.

---

## 2) Files read

Location: `srcs/requirements/wordpress/`
- `Dockerfile` — builds the image with PHP-FPM and WordPress core.
- `conf/www.conf` — PHP-FPM pool configuration (added).
- `tools/setup.sh` — entrypoint that prepares `wp-config.php`, permissions and runs PHP-FPM (added).

---

## 3) Request flow

Browser
→ NGINX (HTTPS)
→ WordPress (PHP-FPM) — `fastcgi_pass wordpress:9000`
→ MariaDB (SQL)

Nginx serves static files directly from the shared WordPress volume. PHP requests are forwarded to this container's PHP-FPM process.

---

## 4) Relationship: NGINX, PHP-FPM, WordPress, MariaDB

- `NGINX`: TLS termination and static content delivery; FastCGI proxy for `.php` requests.
- `PHP-FPM` (in WordPress container): executes PHP code (WordPress) and returns HTML to NGINX.
- `WordPress`: PHP application files stored under `/var/www/html` (shared volume).
- `MariaDB`: database backend; WordPress connects using DB credentials.

Why PHP-FPM is required:
- NGINX does not embed a PHP interpreter. PHP-FPM is a fast CGI process manager that runs PHP code; NGINX proxies PHP requests to it over FastCGI.

---

## 5) Line-by-line explanation — Dockerfile

File: `srcs/requirements/wordpress/Dockerfile`

1. `FROM debian:bookworm` — Debian base (allowed by subject).

3-12. Install required packages:
  - `php-fpm`: PHP FastCGI Process Manager.
  - `php-mysql`: PHP MySQL/MariaDB extension to allow DB access.
  - `php-cli`: command-line PHP (used by WP-CLI if added).
  - `php-curl`, `php-gd`, `php-mbstring`, `php-xml`, `php-zip`: common WordPress extensions.
  - `curl`: fetch WordPress and salts.
  - `mariadb-client`: client utilities (optional) for debugging.

13. `RUN mkdir -p /var/www/html` — ensure web root exists.

15-18. Download and extract WordPress core from `wordpress.org` into `/var/www/html`.

20. `COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf` — put PHP-FPM pool config. (Matches Debian package's php version.)

22-24. Copy and make `tools/setup.sh` executable; this script prepares `wp-config.php`, sets permissions, and starts PHP-FPM.

26. `WORKDIR /var/www/html` — default working directory.

28. `EXPOSE 9000` — declares PHP-FPM port (internal only).

30. `ENTRYPOINT ["/setup.sh"]` — start entrypoint that runs PHP-FPM in foreground.

---

## 6) Line-by-line explanation — `conf/www.conf`

Key directives:
- `user` / `group`: run workers as `www-data`.
- `listen = 9000`: listen on TCP port 9000 (fastcgi via NGINX `fastcgi_pass wordpress:9000`).
- `listen.owner`/`listen.group`: owner/group for the listening socket/port.
- `pm` settings: control PHP-FPM processes (dynamic pool with small defaults suitable for evaluation).

This file ensures PHP-FPM listens on the expected port and runs worker processes as `www-data` so file permissions work.

---

## 7) Line-by-line explanation — `tools/setup.sh`

What it does:
- Reads DB env vars (`MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, optional `DB_HOST`).
- If `wp-config.php` is absent, copies `wp-config-sample.php` and replaces placeholder DB constants with environment values.
- Adds authentication salts via WordPress API (or generates fallback keys).
- Sets ownership to `www-data:www-data` and permissive file/dir modes (files 644, dirs 755).
- Starts PHP-FPM in foreground using `exec` (PID 1), avoiding hacky loops.

This prepares WordPress to connect to MariaDB when NGINX forwards requests.

---

## 8) Environment variables

Core DB variables used (from `srcs/.env`):
- `MYSQL_DATABASE` → database name
- `MYSQL_USER` → DB user
- `MYSQL_PASSWORD` → DB password
- `DB_HOST` (optional) → DB host (defaults to service name `mariadb`)

Notes: variables are used by `setup.sh` to generate `wp-config.php`. No secrets were added to Dockerfiles.

---

## 9) Volumes and persistence

- `docker-compose.yml` binds the named volume `wordpress_data` to `/var/www/html` inside the container, so WordPress files, uploads and plugins persist across container restarts.

---

## 10) Checklist (mandatory)

✅ Correct implementations
- WordPress runs in its own container. ✅
- PHP-FPM is installed and configured to listen on port 9000. ✅
- WordPress files are stored in `/var/www/html` and persisted via a volume. ✅
- Entry script prepares `wp-config.php` from env vars and sets permissions. ✅
- PHP-FPM runs as PID 1 (via `exec`) — no infinite-loop hacks. ✅

⚠ Possible problems
- No automatic WordPress admin user creation implemented; evaluation may require creating admin account manually or adding WP-CLI and automating install.
- Using external `curl` to fetch salts depends on network availability; fallback generates simple salts.

❌ Missing requirements
- Automatic WordPress admin user creation (subject requires an admin user in WordPress DB). ❌ (not implemented)

---

## 11) What I changed (minimal)

- Renamed/ensured `Dockerfile` is present for Compose builds.
- Added `conf/www.conf` to configure PHP-FPM pool listening on 9000 as `www-data`.
- Added `tools/setup.sh` to generate `wp-config.php` from `.env`, set permissions, and start PHP-FPM in foreground.

Why these minimal edits:
- The original `Dockerfile` referenced `conf/www.conf` and `tools/setup.sh` but they were missing; adding them is necessary for WordPress+PHP-FPM to operate and integrate with NGINX.

---

## 12) How to test the WordPress container

1. Build WordPress image only:
```bash
cd srcs
docker compose build wordpress
```
2. Start WordPress (after MariaDB is up):
```bash
docker compose up -d wordpress
```
3. Check PHP-FPM is running and listening on 9000 inside container:
```bash
docker compose exec wordpress ss -ltnp | grep 9000
```
4. Verify `wp-config.php` exists and contains correct DB values:
```bash
docker compose exec wordpress cat /var/www/html/wp-config.php | sed -n '1,80p'
```
5. Visit site through NGINX at `https://<login>.42.fr` to continue WordPress web install or verify site behavior. If admin user creation is required, use the web installer or add WP-CLI to automate it.

---

## 13) Common evaluation Q&A (WordPress + PHP-FPM)

Q: Why is PHP-FPM needed?
A: NGINX delegates PHP execution to PHP-FPM (FastCGI). PHP-FPM runs PHP as separate processes and returns output to NGINX.

Q: Where do WordPress files live?
A: `/var/www/html` inside the `wordpress` container; persisted via named volume `wordpress_data` mapped to `/home/<login>/data/wordpress` on the host.

Q: How is the DB configured?
A: `tools/setup.sh` injects DB constants into `wp-config.php` using env vars from `srcs/.env`.

Q: Is an admin user created automatically?
A: Not by default in this minimal implementation. You can either complete the web install via the browser or extend `setup.sh` to use WP-CLI for automated installation.

---

End of document.
