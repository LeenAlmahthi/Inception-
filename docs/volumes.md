# Volumes and Data Persistence (Inception — Mandatory only)

This document analyzes the project's Docker volumes, how persistence is implemented, and how to verify that data survives container recreation. It follows the Mandatory subject rules only.

---

**1) Discovered volumes (from `srcs/docker-compose.yml`)**

- Volume name: `mariadb_data`
  - Container(s) using it: `mariadb`
  - Host path: `/home/${USER}/data/mariadb` (expanded by Compose from the shell variable `${USER}` at runtime)
  - Container path: `/var/lib/mysql`
  - Type of storage: Docker named volume using `local` driver with `driver_opts` set to perform a host bind mount (i.e., bind mount to a host path)
  - Purpose: Persistent storage for MariaDB data directory (database files, InnoDB tablespace files, binary logs, etc.)

- Volume name: `wordpress_data`
  - Container(s) using it: `wordpress`, `nginx` (nginx mounts it read-only in practice via the same volume)
  - Host path: `/home/${USER}/data/wordpress` (expanded by Compose)
  - Container path: `/var/www/html`
  - Type of storage: Docker named volume using `local` driver with `driver_opts` bind to a host path
  - Purpose: Persistent storage for WordPress application files, uploaded media, and generated files (core files may be present but uploads/content must persist here).

Notes:
- The `volumes:` top-level section in `srcs/docker-compose.yml` defines both volumes with `driver: local` and `driver_opts` that mount a host path (bind). This creates a named Docker volume that is backed by a host directory, satisfying the subject requirement that data be stored under `/home/<login>/data` on the host.

---

**2) Location of related scripts and Makefile targets**

- `Makefile` at project root contains `data_dirs` target that creates the host directories used by the volume binds:
  - `$(DATA_DIR) = /home/$(USER)/data`
  - `DB_DATA_DIR = $(DATA_DIR)/mariadb`
  - `WP_DATA_DIR = $(DATA_DIR)/wordpress`
  - `data_dirs` runs `mkdir -p $(DB_DATA_DIR) $(WP_DATA_DIR)` before `up`.

- MariaDB initialization script: `srcs/requirements/mariadb/tools/setup.sh`
  - Initializes `/var/lib/mysql` (database system tables) if empty by running `mariadb-install-db`.
  - Removes stale InnoDB logfiles (`ib_logfile*`) to avoid InnoDB init failures.
  - Starts a temporary server, creates root password, creates DB and user, then starts the final server.
  - Ensures ownership of runtime directories with `chown -R mysql:mysql /run/mysqld "$DATA_DIR"`.

- WordPress setup script: `srcs/requirements/wordpress/tools/setup.sh`
  - Generates `wp-config.php` from `wp-config-sample.php` if not present inside `/var/www/html`.
  - Sets ownership to `www-data:www-data` and sets directory/file permissions (dirs 755, files 644).

- NGINX setup script: `srcs/requirements/nginx/tools/setup.sh`
  - Generates TLS key/cert in `/etc/nginx/ssl` if missing (not part of WordPress/MariaDB persistence but relevant to runtime files).

---

**3) Role of volumes in Docker (concise)**

- Volumes let containers persist data beyond the container lifecycle by storing files outside the container writable layer.
- Volumes (named or bind mounts) can be shared between containers (e.g., `wordpress` and `nginx` sharing `/var/www/html`).
- Using host paths under `/home/<login>/data` satisfies the Inception subject requirement that data must be host-persistent and accessible after container removal.

---

**4) Differences — Named volume vs Bind mount vs Container filesystem**

- Docker named volume (driver: local): managed by Docker. By default Docker stores data under `/var/lib/docker/volumes/...`, but when `driver_opts` with `device` + `type: none` + `o: bind` are used, the named volume is backed by a host directory (effectively a bind mount). Named volumes provide a stable name and can be referenced in Compose.

- Bind mount: directly mounts a host directory into a container (Compose `volumes: - /host/path:/container/path`). Changes on host are visible to the container and vice-versa. Bind mounts depend on the exact host path and permissions.

- Container filesystem (image/writable layer): data written only into the container overlay filesystem is ephemeral. When the container is removed, data in the writable layer is lost unless it is exported or saved into a volume.

---

**5) Why persistent storage is required in Inception (Mandatory)**

- DB data (MariaDB files) must survive container recreation so user sites and database contents remain after container removal or image rebuild.
- WordPress files (uploaded media, themes, plugins, generated files) must persist between container restarts and recreations.
- The subject mandates persistent named volumes mapped to `/home/<login>/data` on the host.

---

**6) What happens to data when containers/images are changed**

- Stopping a container: the container process stops; volumes remain intact on the host. Data is preserved.
- Restarting a container: container process restarts, mounts the same volumes — data remains available.
- Removing a container (`docker compose rm` / `docker rm`): the container instance is removed but named volumes remain (unless `docker compose down -v` or `docker volume rm` is used). Data persists.
- Rebuilding an image (`docker compose build`): images are rebuilt; existing named volumes are unaffected. When new containers are started using rebuilt images, they mount the same volumes and existing data remains available.
- Rebuilding the whole project and running `docker compose down -v` will remove named volumes and their data. A plain `docker compose down` (no `-v`) keeps volumes.

---

**7) Comparison with Mandatory requirements — checklist**

✅ Correct implementations:
- Volumes are defined in `srcs/docker-compose.yml` and use host paths under `/home/${USER}/data` via `device: /home/${USER}/data/...` — this satisfies the requirement to persist data under `/home/<login>/data`.
- MariaDB uses `/var/lib/mysql` as container path for DB files — correct.
- WordPress uses `/var/www/html` for application files/uploads — correct.
- `Makefile` includes `data_dirs` target that creates the host directories before `up` — helpful and correct.
- Setup scripts set ownership (`chown`) and sensible permissions for runtime users (`mysql` and `www-data`) — improves success on first run.

⚠ Possible problems:
- The Compose file uses `${USER}` for host path expansion; if `docker compose` is invoked from a different shell or CI without `${USER}` set, paths may resolve incorrectly. Ensure the host environment sets `USER` correctly or replace with an explicit path during evaluation.
- We cannot directly verify host directory existence or ownership within this environment (workspace-limited); tests below are provided for the user to run locally.
- If the host `data` directories already contain files with incompatible ownership/permissions, initial container startup may need extra permission fixes (scripts attempt to chown, but in some environments bind-mounts may prevent chown from taking effect due to OS permissions / user namespace restrictions).

❌ Missing requirements:
- None detected in the Mandatory scope: volumes are implemented and bound to `/home/${USER}/data/*` as required. There are no bonus features (Docker secrets, external storage drivers) detected.

---

**8) Verification checklist and found status**

- MariaDB database files are persistent: Implementation uses `mariadb_data` bound to `/home/${USER}/data/mariadb` → OK (by config). Manual runtime verification steps provided below.
- WordPress files are persistent: Implementation uses `wordpress_data` bound to `/home/${USER}/data/wordpress` → OK (by config).
- Volumes are correctly mounted in Compose: `volumes:` mapped to container paths `/var/lib/mysql` and `/var/www/html` → OK.
- Data survives container recreation: Named volumes backed by host bind paths preserve files across `docker compose down` (without `-v`) and container removal → OK (by design).
- Volume paths are correct: container paths follow standard expectations for MariaDB and WordPress → OK.
- Permissions allow containers to work: setup scripts call `chown` and set permissions; this covers typical cases. Edge cases may arise due to host filesystem restrictions → Mostly OK; verify locally.
- No data stored only inside the container filesystem: All runtime data paths are bound to volumes → OK.
- No Bonus requirements implemented: No Docker secrets or extra storage drivers detected → OK.

Limitations: I cannot access host `/home/<login>/data` directories from this environment to confirm actual files; please run the verification commands below on your machine.

---

**9) Suggested minimal checks and remediation (if problems found)**

If you encounter permission issues (database fails to start, InnoDB errors, or WordPress cannot write uploads):
- Ensure host directories exist and are writable by Docker. Run on host:

```bash
mkdir -p /home/$USER/data/mariadb /home/$USER/data/wordpress
sudo chown -R 1000:1000 /home/$USER/data/mariadb /home/$USER/data/wordpress
```

- Alternatively let the `Makefile` create directories and let container entrypoints `chown` the mounted directories; if chown cannot change ownership due to host restrictions, adjust host permissions or run containers with appropriate user namespaces.

Do NOT change the volume architecture — it already matches the Mandatory requirements.

---

**10) How to test persistence (commands to run locally)**

Run these commands from `srcs/` (where `docker-compose.yml` is located):

1) Create data directories and start stack:

```bash
# from project root
make data_dirs
cd srcs
docker compose up --build -d
```

2) Verify mounts inside containers:

```bash
# MariaDB mounted path
docker compose exec mariadb sh -c 'ls -la /var/lib/mysql | sed -n "1,120p"'

# WordPress mounted path
docker compose exec wordpress sh -c 'ls -la /var/www/html | sed -n "1,120p"'
```

3) Create test artifacts and verify persistence across recreation:

```bash
# Create a test file in WordPress uploads
docker compose exec wordpress sh -c 'mkdir -p /var/www/html/wp-content/uploads/test && echo "persisted" > /var/www/html/wp-content/uploads/test/keep.txt'

# Create a test DB entry
docker compose exec mariadb sh -c "mariadb -uroot -p\"$MYSQL_ROOT_PASSWORD\" -e \"CREATE DATABASE IF NOT EXISTS persist_test; USE persist_test; CREATE TABLE t (i INT); INSERT INTO t VALUES (1);\""

# Stop and remove containers (keep volumes)
docker compose down

# Start containers again
docker compose up -d

# Verify the WordPress file exists
docker compose exec wordpress sh -c 'cat /var/www/html/wp-content/uploads/test/keep.txt'

# Verify DB entry exists
docker compose exec mariadb sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM persist_test.t;"'
```

If both readouts show the created data, persistence works.

To simulate destructive removal (what deletes data):

```bash
# This will remove named volumes declared in compose (data lost)
docker compose down -v
```

---

**11) Common 42 evaluation Q&A (Volumes)**

Q: Where must persisted data be stored for the evaluation?
A: Under `/home/<login>/data` on the host as specified in the subject; this project binds volumes to `/home/${USER}/data/...`.

Q: Are named volumes allowed?
A: Yes — but the subject requires that the host path be under `/home/<login>/data`. This project uses named volumes backed by host bind paths, meeting the requirement.

Q: Will `docker compose down` delete my data?
A: `docker compose down` without `-v` keeps volumes and data. `docker compose down -v` removes volumes.

Q: How do I back up MariaDB data?
A: Use `mysqldump` or copy the host data directory while MariaDB is stopped. `mysqldump` is generally safer.

Q: Are permissions handled automatically?
A: The container entrypoint scripts attempt to `chown` the mounted directories. If host permissions block chown, you may need to adjust host permissions before first run.

---

**12) Files changed/created by this analysis**

- Added: `docs/volumes.md` (this file).

---

End of document.
