# NGINX container analysis (42 Inception — Mandatory only)

## Scope and source of truth
This document analyzes only the **NGINX service** for the **Mandatory** part of the official Inception subject.
No Bonus requirements are covered.

Subject points used for this analysis (mandatory):
- NGINX must run in its own container.
- NGINX must use TLSv1.2 or TLSv1.3 only.
- The project must use Docker Compose.
- Dockerfiles must be used (built locally, no ready-made service images).
- No forbidden hacky infinite-loop entrypoint patterns.

---

## 1) Purpose of the NGINX container in Inception

The NGINX container is the **single public entrypoint** of the infrastructure.
Its role is to:
- terminate HTTPS/TLS on port 443,
- receive browser requests,
- serve static WordPress files from the shared WordPress volume,
- forward PHP requests to the WordPress PHP-FPM service (`wordpress:9000`) on the internal Docker network.

NGINX does **not** contain MariaDB and does **not** run WordPress itself; it is the front web server/reverse proxy layer.

---

## 2) Complete request flow

Browser
→ HTTPS request to `https://<login>.42.fr` on port 443
→ NGINX container accepts TLS and parses request
→ If static file exists, NGINX serves it directly from `/var/www/html`
→ If request needs PHP processing (`.php`), NGINX forwards to `wordpress:9000` via FastCGI
→ WordPress PHP code executes in WordPress container
→ WordPress queries MariaDB container over internal network
→ Response goes back: MariaDB → WordPress/PHP-FPM → NGINX → Browser

---

## 3) Files read for NGINX analysis

Inside `srcs/requirements/nginx/`:
- `Dockerfile`
- `conf/nginx.conf`
- `tools/setup.sh`

Certificate files are **not stored statically** in repository for this service.
They are generated at container startup by `setup.sh` into:
- `/etc/nginx/ssl/inception.crt`
- `/etc/nginx/ssl/inception.key`

---

## 4) Line-by-line explanation — Dockerfile

File: `srcs/requirements/nginx/Dockerfile`

### Line 1
`FROM debian:bookworm`
- Uses Debian Bookworm as base image.
- Mandatory-compatible because official subject allows Alpine or Debian stable family.

### Line 2
(blank)
- Readability separator.

### Lines 3–5
`RUN apt-get update && \`
`    apt-get install -y --no-install-recommends nginx openssl && \`
`    rm -rf /var/lib/apt/lists/*`
- `apt-get update`: refresh package index before install.
- `apt-get install ... nginx openssl`: installs:
  - `nginx`: web server that handles HTTPS and reverse proxying.
  - `openssl`: used to create a TLS certificate and key.
- `--no-install-recommends`: keeps image smaller by avoiding optional packages.
- `rm -rf /var/lib/apt/lists/*`: removes apt metadata cache to reduce final image size.

### Line 6
(blank)
- Readability separator.

### Lines 7–8
`RUN mkdir -p /etc/nginx/ssl && \`
`    rm -f /etc/nginx/sites-enabled/default`
- Creates directory where certificate and key will be stored.
- Removes Debian default HTTP site config to avoid default port 80 behavior and enforce HTTPS-only service design.

### Line 9
(blank)

### Line 10
`COPY conf/nginx.conf /etc/nginx/conf.d/default.conf`
- Copies custom NGINX virtual host config into container.
- This is the active site config used by NGINX.

### Line 11
`COPY tools/setup.sh /setup.sh`
- Copies startup script used as container entrypoint.

### Line 12
`RUN chmod +x /setup.sh`
- Makes entrypoint script executable.

### Line 13
(blank)

### Line 14
`EXPOSE 443`
- Documents intended service port inside container (HTTPS).

### Line 15
(blank)

### Line 16
`ENTRYPOINT ["/setup.sh"]`
- Container starts through `setup.sh`.
- Script generates certificate if missing and then `exec`s NGINX in foreground (PID 1 best practice).

---

## 5) Line-by-line explanation — nginx.conf

File: `srcs/requirements/nginx/conf/nginx.conf`

### Line 1
`server {`
- Starts one server block (virtual host definition).

### Line 2
`listen 443 ssl;`
- Listen on IPv4 port 443 with SSL/TLS enabled.

### Line 3
`listen [::]:443 ssl;`
- Listen on IPv6 port 443 with SSL/TLS enabled.

### Line 4
(blank)

### Line 5
`server_name _;`
- Catch-all server name for requests that do not match a specific host.
- Keeps config simple for local evaluation while domain resolves to VM IP.

### Line 6
(blank)

### Line 7
`ssl_certificate /etc/nginx/ssl/inception.crt;`
- Path to TLS certificate used by NGINX.

### Line 8
`ssl_certificate_key /etc/nginx/ssl/inception.key;`
- Path to private key paired with certificate.

### Line 9
`ssl_protocols TLSv1.2 TLSv1.3;`
- Restricts accepted TLS protocols to mandatory-required secure versions only.

### Line 10
`ssl_prefer_server_ciphers on;`
- Instructs NGINX to prefer server cipher choice for stronger negotiation control.

### Line 11
(blank)

### Line 12
`root /var/www/html;`
- Document root containing WordPress files mounted from shared volume.

### Line 13
`index index.php index.html;`
- Default index files priority.
- Ensures WordPress (`index.php`) is handled by default.

### Line 14
(blank)

### Lines 15–17
`location / {`
`    try_files $uri $uri/ /index.php?$args;`
`}`
- Tries static file first (`$uri`, `$uri/`).
- If missing, rewrites to `index.php` with original query args.
- This is essential for WordPress permalink routing.

### Line 18
(blank)

### Lines 19–24
`location ~ \.php$ {`
`    include snippets/fastcgi-php.conf;`
`    fastcgi_pass wordpress:9000;`
`    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;`
`    include fastcgi_params;`
`}`
- Matches PHP requests.
- Includes standard fastcgi parameters/snippets for PHP handling.
- `fastcgi_pass wordpress:9000` sends PHP execution to PHP-FPM in WordPress container by service DNS name on Docker network.
- `SCRIPT_FILENAME` passes resolved script path to PHP-FPM.

### Line 25
`}`
- Ends server block.

---

## 6) Line-by-line explanation — setup.sh

File: `srcs/requirements/nginx/tools/setup.sh`

### Line 1
`#!/bin/sh`
- POSIX shell interpreter declaration.

### Line 2
`set -eu`
- `-e`: exit immediately on command error.
- `-u`: fail on unset variables.
- Improves script safety for container startup.

### Line 3
(blank)

### Line 4
`SSL_DIR="/etc/nginx/ssl"`
- Directory containing TLS files.

### Line 5
`CERT_FILE="$SSL_DIR/inception.crt"`
- Full certificate output path.

### Line 6
`KEY_FILE="$SSL_DIR/inception.key"`
- Full private key output path.

### Line 7
`DOMAIN="${DOMAIN_NAME:-localhost}"`
- Uses `DOMAIN_NAME` env var if present, otherwise defaults to `localhost`.
- Used for certificate subject CN.

### Line 8
(blank)

### Lines 9–14
`if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then`
`    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \`
`        -keyout "$KEY_FILE" \`
`        -out "$CERT_FILE" \`
`        -subj "/C=MA/ST=Casablanca/L=Casablanca/O=42/OU=Inception/CN=$DOMAIN"`
`fi`
- Checks if certificate or key missing.
- Generates a self-signed X.509 certificate and RSA 2048 key:
  - `-x509`: self-signed cert output.
  - `-nodes`: do not encrypt private key with passphrase.
  - `-newkey rsa:2048`: create new 2048-bit RSA key.
  - `-days 365`: validity period.
  - `-keyout`: where to store key.
  - `-out`: where to store certificate.
  - `-subj`: non-interactive subject fields.
- Idempotent: does not regenerate if files already exist.

### Line 15
(blank)

### Line 16
`exec nginx -g 'daemon off;'`
- Replaces shell with NGINX process (`exec`) so NGINX becomes PID 1.
- `daemon off;` keeps NGINX in foreground (container best practice).
- No forbidden infinite-loop hack is used.

---

## 7) Mandatory checklist for NGINX service

### ✅ Correct implementations
- NGINX runs in its own dedicated service/container.
- NGINX image is built from local Dockerfile (not pulled as prebuilt service image).
- NGINX listens on port 443 with SSL enabled.
- `ssl_protocols` restricts to `TLSv1.2` and `TLSv1.3` only.
- NGINX forwards PHP to WordPress via FastCGI (`wordpress:9000`).
- Startup runs `nginx -g 'daemon off;'` (no forbidden loop hacks).
- Docker Compose publishes `443:443` for NGINX service.

### ⚠ Possible problems to watch during evaluation
- Certificate is self-signed; browser will warn unless CA trusted (acceptable for this project context).
- If WordPress PHP-FPM is not listening on 9000 in its own container, NGINX `fastcgi_pass` will fail.
- Domain mapping (`<login>.42.fr`) must resolve to VM IP in host setup; otherwise evaluator may fail DNS/host test.

### ❌ Missing requirements (after fix)
- None identified at NGINX container level for mandatory scope.

---

## 8) What was incorrect before and what was changed

### Detected issues before fix
1. `srcs/requirements/nginx/` had only one file: lowercase `dockerfile`.
2. Dockerfile referenced files that did not exist:
   - `conf/nginx.conf`
   - `tools/setup.sh`
3. This caused NGINX image build to be non-functional.
4. Default Debian NGINX site could keep HTTP defaults active (undesired for HTTPS-only intent).

### Minimal required changes applied
- Renamed file to `Dockerfile` (Compose default lookup).
- Added `conf/nginx.conf` with mandatory HTTPS + FastCGI forwarding.
- Added `tools/setup.sh` to generate certs and start NGINX correctly.
- Updated Dockerfile to remove default site and keep only needed behavior.

No bonus feature was introduced.
Architecture remained unchanged (NGINX ↔ WordPress ↔ MariaDB).

---

## 9) TLS and certificate explanation

- TLS is enabled directly in NGINX server block (`listen 443 ssl`).
- Protocols are restricted to secure versions only (`TLSv1.2 TLSv1.3`).
- Certificate and key are generated at container startup by OpenSSL if missing.
- Paths:
  - Certificate: `/etc/nginx/ssl/inception.crt`
  - Key: `/etc/nginx/ssl/inception.key`
- Because generation is automated, no private key is stored in repository files.

---

## 10) Port explanation

- Container exposes internal port `443` in Dockerfile.
- Compose maps host `443` to container `443`.
- No mandatory HTTP (port 80) publishing is used.
- This enforces NGINX as HTTPS entrypoint.

---

## 11) Communication with WordPress

- NGINX never executes PHP itself.
- PHP requests are sent to `wordpress:9000` over Docker internal network.
- Service name `wordpress` is resolved by Docker DNS because both services share the compose network.
- WordPress then accesses MariaDB over the same network.

---

## 12) Common 42 evaluation questions (NGINX) and concise answers

1. **Why do you need NGINX if WordPress exists?**
   - NGINX is the web/TLS front layer; WordPress runs PHP-FPM backend only.

2. **Where is TLS configured?**
   - In NGINX server block via `listen ... ssl`, `ssl_certificate`, `ssl_certificate_key`, and `ssl_protocols`.

3. **How do you guarantee TLSv1.2/1.3 only?**
   - `ssl_protocols TLSv1.2 TLSv1.3;` in NGINX config.

4. **How are PHP files processed?**
   - `location ~ \.php$` forwards to `fastcgi_pass wordpress:9000` (PHP-FPM).

5. **Why `daemon off;`?**
   - Container needs foreground main process; this keeps NGINX as PID 1.

6. **Are forbidden infinite loops used?**
   - No. Startup script ends with `exec nginx -g 'daemon off;'`.

7. **Where are certificates stored?**
   - Inside container at `/etc/nginx/ssl/` (generated by setup script).

8. **Does NGINX talk directly to MariaDB?**
   - No. NGINX talks to WordPress/PHP-FPM only.

9. **Why remove default NGINX site?**
   - To avoid unintended HTTP defaults and keep explicit custom HTTPS config.

10. **How can you prove NGINX is the only entrypoint?**
   - Compose publishes only NGINX `443:443`; WordPress/MariaDB are not publicly published.

---

## 13) How to test NGINX container (mandatory-focused)

1. Build only NGINX image:
   - `docker compose -f srcs/docker-compose.yml build nginx`

2. Start full stack:
   - `docker compose -f srcs/docker-compose.yml up -d`

3. Verify NGINX listens on 443:
   - `docker compose -f srcs/docker-compose.yml exec nginx ss -ltnp | grep 443`

4. Verify TLS protocol restriction:
   - `echo | openssl s_client -connect localhost:443 -tls1_2`
   - `echo | openssl s_client -connect localhost:443 -tls1_3`
   - TLS1.0/1.1 attempts should fail when tested similarly.

5. Verify HTTP is not used as entrypoint:
   - `curl -I http://localhost` should not be the intended access path.
   - `curl -kI https://localhost` should return NGINX response headers.

6. Verify NGINX ↔ WordPress fastcgi path:
   - open WordPress install page in browser through `https://<login>.42.fr`.

---

## 14) Final mandatory status (NGINX scope)

After the minimal fixes, the NGINX implementation is aligned with mandatory expectations at container/config level:
- dedicated NGINX container,
- HTTPS/TLS enabled,
- TLSv1.2/1.3 only,
- port 443 exposed/published,
- proper forwarding to WordPress PHP-FPM,
- no bonus-only features introduced.
