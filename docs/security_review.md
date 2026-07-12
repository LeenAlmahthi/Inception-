# Security & Configuration Review (Inception — Mandatory only)

This document reviews TLS/SSL, certificates, permissions, users/groups, container privileges, environment variables, exposed ports, configuration files, and service security for the Mandatory Inception subject. It documents findings, risks, verification commands, and remediation suggestions without implementing Bonus features.

---

**Summary / high level**

- The project implements HTTPS at the `nginx` service, PHP-FPM in `wordpress`, and MariaDB in `mariadb` service. Only port `443` is published. Services use a private Docker bridge network `inception`.
- TLS keys/certificates are generated at NGINX container startup (`/etc/nginx/ssl/inception.key`, `inception.crt`) using OpenSSL and a CN derived from `DOMAIN_NAME` or `localhost`.
- Database credentials are provided via `srcs/.env` and injected into containers via `env_file:`. `wp-config.php` is generated at container startup by `wordpress/tools/setup.sh` with DB credentials and WP salts.
- The MariaDB init script sets root password and creates an application user with `GRANT ALL PRIVILEGES` on the application database. Init scripts and service entrypoints `chown` runtime directories.

Limitations: I could not inspect host file ownership or runtime container state from this environment; assertions are based on repository files.

---

## NGINX review

Files: `srcs/requirements/nginx/Dockerfile`, `conf/nginx.conf`, `tools/setup.sh`

Findings:
- `nginx.conf` contains `listen 443 ssl;`, `ssl_certificate /etc/nginx/ssl/inception.crt;`, `ssl_certificate_key /etc/nginx/ssl/inception.key;`, and `ssl_protocols TLSv1.2 TLSv1.3;` — TLS protocols restricted to TLS1.2+ (good).
- `tools/setup.sh` generates a self-signed certificate with `openssl req -x509 -nodes -newkey rsa:2048 -days 365` when needed and stores them in `/etc/nginx/ssl` inside the container.
- Dockerfile uses `EXPOSE 443` and installs `openssl` and `nginx` (allowed for generating certs).

Security implications and suggestions:
- Self-signed certs: appropriate for local evaluation, but not for public production. The private key is stored inside container filesystem. On container recreation these will be regenerated unless persisted. If persistent host storage for certs is required, bind the `/etc/nginx/ssl` directory to a host path under `/home/<login>/data` (optional suggestion only).
- Key protection: ensure container filesystem permissions are restrictive for private keys. The `setup.sh` does not explicitly set restrictive `chmod` on the private key; consider `chmod 600 /etc/nginx/ssl/inception.key` inside `setup.sh`.
- TLS config: `ssl_protocols TLSv1.2 TLSv1.3;` is correct. Ensure `ssl_ciphers` is set to a secure modern cipher suite if required by evaluator (optional).
- Published port: Compose publishes `443:443`. Runtime environments that restrict privileged ports may block binding to host 443 (environmental, not configuration issue).

Checks to run locally:
```bash
# Test TLS handshake
echo | openssl s_client -connect localhost:443 -tls1_2

# Inspect cert files inside container
docker compose exec nginx sh -c 'ls -la /etc/nginx/ssl && stat -c "%a %U:%G %n" /etc/nginx/ssl/inception.key /etc/nginx/ssl/inception.crt'
```

---

## MariaDB review

Files: `srcs/requirements/mariadb/Dockerfile`, `conf/50-server.cnf`, `tools/setup.sh`

Findings:
- `tools/setup.sh` requires `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` from environment and fails early if missing (good fail-fast).
- Initialization sequence: `mariadb-install-db` if datadir empty, remove stale `ib_logfile*`, start temporary server with `--skip-networking`, run SQL to `ALTER USER 'root'@'localhost' IDENTIFIED BY ...`, `CREATE DATABASE ...`, `CREATE USER ...@'%' IDENTIFIED BY ...'` and `GRANT ALL PRIVILEGES ON db.* TO user@'%'`.
- Final server executes as `mariadbd --user=mysql ... --bind-address=0.0.0.0` — MariaDB listens on all interfaces inside the container (necessary for Docker networking) but Compose does not publish port 3306.
- Data dir is `/var/lib/mysql` and is persisted via named volume bind to `/home/${USER}/data/mariadb`.

Security implications and suggestions:
- Root password handling: root password is set at initialization and not hardcoded — good. Ensure `srcs/.env` is not committed publicly (it currently appears in repo) — this is a security risk. Recommendation: remove `srcs/.env` from the repo and add to `.gitignore`, or rotate credentials before publishing.
- Application user privileges: `GRANT ALL PRIVILEGES ON db.*` is acceptable for a single-application DB but follows principle of least privilege only if the user is restricted to the specific database (it is). Do not grant global privileges.
- Binding to `0.0.0.0` is fine for containerized internal networking. Verify no `ports:` publish 3306.
- File permissions: `setup.sh` runs `chown -R mysql:mysql` on runtime dirs — good. Ensure host bind mount permissions allow `chown` to take effect; if host FS prevents chown, MariaDB may fail to start.

Checks to run locally:
```bash
# Confirm DB not published
docker compose ps
# Inspect MariaDB logs
docker compose logs mariadb --tail=200
# Check DB users
docker compose exec mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User,Host,Authentication_string IS NOT NULL FROM mysql.user;"
``` 

---

## WordPress review

Files: `srcs/requirements/wordpress/Dockerfile`, `conf/www.conf`, `tools/setup.sh`

Findings:
- `tools/setup.sh` generates `wp-config.php` from sample and injects DB credentials and DB host. It appends salts fetched from `https://api.wordpress.org/secret-key/1.1/salt/` if `curl` is present, otherwise generates random keys locally.
- `setup.sh` writes `wp-config.php` into `/var/www/html` (the WordPress volume) and sets ownership `www-data:www-data` and permissions: directories `755` and files `644`.
- PHP-FPM pool (`www.conf`) is configured with `user = www-data`, `group = www-data`, `listen = 9000` (TCP), and `listen.owner/listen.group = www-data`.
- Dockerfile `EXPOSE 9000` (internal only); no published host port.

Security implications and suggestions:
- `wp-config.php` contains DB credentials and salts — these are sensitive. The file is owned by `www-data` and set to 644 (owner writable), which is standard for web apps. Consider restricting `wp-config.php` to `640` or `600` if environment allows; ensure `www-data` can still read it.
- Salts: fetching from WordPress API is good; fallback to local randomness is acceptable. Confirm `curl` is available in image; if not, local generation runs.
- No automatic admin user creation is implemented — the subject may expect an admin account; this is a functional, not security, gap (documented elsewhere).
- PHP-FPM runs as `www-data` — least privilege for PHP workers is good. Entrypoint uses `exec` to run php-fpm in foreground.

Checks to run locally:
```bash
# View wp-config permissions
docker compose exec wordpress sh -c 'stat -c "%a %U:%G %n" /var/www/html/wp-config.php || true'
# Confirm PHP-FPM listening on TCP 9000
docker compose exec wordpress ss -ltnp | grep 9000 || true
``` 

---

## Docker and container security

Findings:
- Dockerfiles use `EXPOSE` where appropriate; Compose publishes only `443:443` for `nginx`.
- Entrypoints and setup scripts use `exec` to run services as PID 1 where appropriate (good practice).
- Containers run service processes as non-root users where supported: MariaDB runs as `mysql` (`--user=mysql` in server invocation), PHP-FPM configured to run workers as `www-data`. NGINX default runs as `www-data` from package configuration (Dockerfile did not switch to a different user). No `USER` directive in Dockerfiles was discovered that enforces non-root at build-time, but runtime processes run under service users via configuration or server flags.
- No CAP_ADD, privileged: true, or other elevated Docker options found — good.

Security implications and suggestions:
- Consider adding explicit `USER` in Dockerfiles where feasible to reduce build-time surprises; however packages and service start may require `root` at build and during container startup to create certain files. Current runtime use of service users is acceptable for the Mandatory scope.
- Environment variables: credentials are supplied via `srcs/.env` and passed into containers. Committed `.env` is a risk. Use local `.env` not committed.

Checks to run locally:
```bash
# List containers and published ports
docker compose ps
# Inspect container processes and users
docker compose exec wordpress ps aux | head -n 20
docker compose exec mariadb ps aux | head -n 20
docker compose exec nginx ps aux | head -n 20
``` 

---

## Security concepts explained (brief)

- TLS/SSL: cryptographic protocols providing confidentiality and integrity for transport. NGINX terminates TLS with a certificate/private key pair.
- Certificates & private keys: certificate is public, private key must be kept secret; private key permissions should be restrictive.
- Ownership & permissions: file owner and permission masks control which users can read/write. Use least privilege: only the process user should have write access.
- Users/groups: services run worker processes as unprivileged users (e.g., `www-data`, `mysql`) instead of `root` to limit impact of compromise.
- Environment variables: convenient for configuration but can leak secrets if committed or logged; treat `.env` as sensitive.

---

## Checklist: Correct / Concerns / Missing

✅ Correct implementations
- HTTPS termination at `nginx` with `listen 443 ssl` and TLSv1.2/TLSv1.3 enforced. ✅
- Only port published to host is `443`; DB and PHP-FPM ports are internal. ✅
- Services run worker processes under non-root users (`mysql`, `www-data`) at runtime. ✅
- Init scripts set ownership and create DB, users, and run server processes via `exec`. ✅

⚠ Security concerns
- `srcs/.env` appears committed with DB credentials — this is a significant risk; remove from repo and add to `.gitignore`. ⚠
- NGINX private key is created inside container and not explicitly permission-restricted; consider `chmod 600` on the key. ⚠
- Generated certificates are ephemeral unless persisted; re-creating containers regenerates certs (acceptable for local eval, note the implication). ⚠
- `CREATE USER '...'%` allows remote connections from any host — within Docker network this is acceptable, but restrict host to service-level if desired. ⚠
- `GRANT ALL PRIVILEGES` is acceptable scoped to DB but avoid global grants. ⚠
- Some Dockerfiles do not include a build-time `USER` directive; services rely on runtime config. This is acceptable but be aware builds run as root.

❌ Missing requirements
- No explicit missing Mandatory security requirements found. (Admin user creation for WordPress is a functional requirement handled elsewhere.) ❌

---

## If changes are required (high level)

- Problem: `srcs/.env` contains secrets committed to the repo.
  - Rationale: secrets in Git history are a failure mode for submission.
  - Suggested minimal action (do not run without confirmation): remove `srcs/.env` from index and add to `.gitignore`, then provide evaluator with credentials separately. Use `git rm --cached srcs/.env` and commit.

- Problem: private key permission not enforced after generation.
  - Suggested minimal edit: in `srcs/requirements/nginx/tools/setup.sh` after key creation add `chmod 600 "$KEY_FILE" && chown root:root "$KEY_FILE"`.

I will not apply these changes automatically without your approval.

---

## Verification commands (run locally from project root)

1) Confirm only port 443 published:
```bash
docker compose -f srcs/docker-compose.yml ps
```

2) Inspect NGINX TLS and cert files:
```bash
docker compose -f srcs/docker-compose.yml exec nginx sh -c 'ls -la /etc/nginx/ssl && openssl x509 -in /etc/nginx/ssl/inception.crt -noout -text | sed -n "1,60p"'
```

3) Check private key permissions (recommend to run):
```bash
docker compose exec nginx sh -c 'stat -c "%a %U:%G %n" /etc/nginx/ssl/inception.key'
```

4) Confirm MariaDB user and DB exist:
```bash
docker compose exec mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User,Host FROM mysql.user; SHOW DATABASES;"
```

5) Confirm `wp-config.php` ownership and contents:
```bash
docker compose exec wordpress sh -c 'stat -c "%a %U:%G %n" /var/www/html/wp-config.php; sed -n "1,60p" /var/www/html/wp-config.php'
```

6) Confirm processes run as expected and ports only internal:
```bash
docker compose exec wordpress ss -ltnp | grep 9000 || true
docker compose exec mariadb ss -ltnp | grep 3306 || true
docker compose exec nginx ss -ltnp | grep 443 || true
```

---

## Files changed/created by this report

- Added: `docs/security_review.md` (this file).

---

End of security review.
