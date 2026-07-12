# Docker Networks (Inception — Mandatory only)

This document analyzes the project's Docker networking, how containers communicate, and how to verify connectivity. It follows the Mandatory subject rules only.

---

**1) Networks discovered (from `srcs/docker-compose.yml`)**

- Network name: `inception`
  - Type: `bridge` (user-defined bridge network)
  - Containers connected: `mariadb`, `wordpress`, `nginx`
  - Purpose: internal application network for inter-service communication (DB, PHP-FPM, Nginx). Keeps traffic isolated from other user-defined networks while allowing service name resolution.

Notes: No other networks are declared. No `host` network mode is used.

---

**2) Role of Docker networks (concise)**

- Provide isolated L3/L4 connectivity between containers.
- Enable automatic DNS resolution of service names when containers are attached to the same user-defined network.
- Control reachability to services and which ports must be published to the host for external access.

---

**3) Differences and definitions**

- Internal container communication: traffic between containers on the same Docker network (e.g., `wordpress` -> `mariadb`). Uses container IPs and service names; not visible outside the Docker host unless explicitly published.

- Published ports (`ports` in Compose): map a container port to the host (e.g., `"443:443"` publishes container 443 to host 443). This enables host/external clients to reach the container.

- Exposed ports (`EXPOSE` in Dockerfile or `expose:` in compose): a documentation/networking hint that the container listens on a port; does not publish to the host by itself. Docker networks still allow other containers to connect to the exposed port.

- Host-to-container communication: traffic originating from the Docker host or external network to a container via published ports or host networking.

---

**4) How containers find each other**

- Docker provides an embedded DNS server for user-defined networks. When containers are attached to the same network, Docker's DNS resolves service names declared in `docker-compose.yml` into container IPs.
- In this Compose file, service names are `mariadb`, `wordpress`, `nginx`. For example, from `wordpress` container you can connect to `mariadb:3306`.
- Do not use `localhost` to refer to another container — `localhost` refers to the container's own loopback interface. Use the service name.

---

**5) Network flow (External user → MariaDB)**

Browser
  |
  | HTTPS :443 (published on host -> container)
  v
NGINX container (listens on 443)
  |
  | FastCGI (nginx -> php-fpm) — tcp connection to `wordpress:9000` (internal network)
  v
WordPress container (PHP-FPM)
  |
  | Database connection — connect to `mariadb:3306` (internal network)
  v
MariaDB container

Notes: FastCGI uses an internal TCP socket (php-fpm listens on 9000 inside `wordpress` container). NGINX proxies requests to `wordpress:9000` via the `inception` bridge network.

---

**6) Comparison with Mandatory requirements — checklist**

✅ Correct implementations
- Single user-defined bridge network `inception` connects all required services. ✅
- Services use service names: `mariadb`, `wordpress`, `nginx` (Compose names) for internal communication. ✅
- Only required host port is published: `443:443` for HTTPS on NGINX. ✅
- No use of `host` network or privileged networking; isolation preserved. ✅

⚠ Possible problems
- The environment where `docker compose` runs must permit binding host port 443 (some environments restrict privileged ports). This is an environment limitation, not a config error. ⚠
- If `wordpress`'s PHP-FPM is configured to listen on a unix socket instead of `0.0.0.0:9000`, nginx->php-fpm TCP proxying would fail. Current `tools/setup.sh` uses `php-fpm -F` and Dockerfile sets `WORKDIR /var/www/html`; ensure PHP-FPM listens on TCP 9000 (the `conf/www.conf` must match). Verify `wordpress` image config. ⚠

❌ Missing requirements
- None for Mandatory: the network is minimal and sufficient. No bonus features (overlay networks, external drivers) detected. ❌

---

**7) Verification checklist & commands (run locally from `srcs/`)

Run these to verify networks and connectivity. Replace `docker compose` with your CLI if different.

1) Show network and connected containers:

```bash
# List networks
docker network ls | grep inception

# Inspect the inception network to see containers attached
docker network inspect inception
```

2) From NGINX container, verify it can resolve and reach `wordpress:9000`:

```bash
# DNS resolution
docker compose exec nginx sh -c 'getent hosts wordpress || true'

# TCP connect (requires nc/netcat in image) - fallback: use curl to http://wordpress:9000 if relevant
docker compose exec nginx sh -c 'nc -zv wordpress 9000 || true'
```

3) From WordPress container, verify it can resolve and connect to `mariadb:3306`:

```bash
docker compose exec wordpress sh -c 'getent hosts mariadb || true'

docker compose exec wordpress sh -c 'nc -zv mariadb 3306 || true'
```

4) Test HTTP flow via NGINX to WordPress:

```bash
# inside host, request https (if cert is self-signed use -k to skip verification)
curl -k https://localhost/ -v
```

5) If `nc` is not available, use `telnet` or install busybox/nc in the container or run a temporary busybox container on the same network:

```bash
docker run --rm -it --network inception busybox sh
# inside busybox run: nslookup wordpress; telnet wordpress 9000
```

Notes: images may not include `nc` or `getent`; use `docker run --rm -it --network inception busybox` to run ad-hoc checks.

---

**8) Additional checks done in repo**

- `srcs/docker-compose.yml` shows `ports: - "443:443"` on `nginx` and no other `ports` entries — only HTTPS is published. ✅
- `networks:` defines `inception` with `driver: bridge` — correct and minimal. ✅
- No containers use `extra_hosts` or `links` (not needed). ✅

---

**9) Common 42 evaluation Q&A (Networking)**

Q: How do containers reach other services?
A: Use the Compose service name as the hostname (e.g., `mariadb`) — Docker's embedded DNS resolves it on the user-defined network.

Q: Can I use `localhost` inside a container to reach another container?
A: No. `localhost` points to the container itself. Use service names or container IPs.

Q: Do I need to publish DB ports to the host?
A: No. Publishing DB ports is unnecessary and reduces security. Internal services should connect via the internal network.

Q: What happens if I run `docker compose down`?
A: Containers are stopped and removed from the network; the user-defined network persists until removed (or recreated by Compose later). Named volumes persist unless `-v` used. Networking configuration in `docker-compose.yml` ensures consistent reconnection on next `up`.

---

**10) Files changed/created by this analysis**

- Added: `docs/networks.md` (this file).

---

End of document.
