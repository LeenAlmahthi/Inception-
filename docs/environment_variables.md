# Environment variables and secrets (42 Inception — Mandatory only)

## Scope
This document documents all environment variables used in the project, where they are defined, where they are used, which container uses them, and security considerations. It covers only the Mandatory part.

---

## 1) All discovered variables

From `srcs/.env`:
- `MYSQL_DATABASE`
- `MYSQL_USER`
- `MYSQL_PASSWORD`
- `MYSQL_ROOT_PASSWORD`

Referenced by code/configs but not defined in `srcs/.env` (can be supplied via environment or `.env` if desired):
- `DB_HOST` (used by WordPress `tools/setup.sh`, defaults to `mariadb`)
- `DOMAIN_NAME` (used by NGINX `tools/setup.sh` for certificate CN)
- `USER` (shell environment substitution used in `docker-compose.yml` volume `device` paths)

No `ENV` instructions are present in Dockerfiles (no hardcoded credentials).

---

## 2) Complete variable table

- `MYSQL_DATABASE`
  - Defined: `srcs/.env`
  - Used: `srcs/requirements/mariadb/tools/setup.sh`, `srcs/requirements/wordpress/tools/setup.sh` (via substitution)
  - Container: `mariadb` (setup), `wordpress` (wp-config generation)
  - Purpose: name of the WordPress database to create and connect to.

- `MYSQL_USER`
  - Defined: `srcs/.env`
  - Used: `srcs/requirements/mariadb/tools/setup.sh`, `srcs/requirements/wordpress/tools/setup.sh`
  - Container: `mariadb`, `wordpress`
  - Purpose: non-root DB user for WordPress application access.

- `MYSQL_PASSWORD`
  - Defined: `srcs/.env`
  - Used: `srcs/requirements/mariadb/tools/setup.sh`, `srcs/requirements/wordpress/tools/setup.sh`
  - Container: `mariadb`, `wordpress`
  - Purpose: password for `MYSQL_USER`.

- `MYSQL_ROOT_PASSWORD`
  - Defined: `srcs/.env`
  - Used: `srcs/requirements/mariadb/tools/setup.sh`
  - Container: `mariadb`
  - Purpose: root password set during DB initialization.

- `DB_HOST`
  - Defined: not defined by default; optional environment variable (can be provided in `.env` or host env)
  - Used: `srcs/requirements/wordpress/tools/setup.sh` (defaults to `mariadb`)
  - Container: `wordpress`
  - Purpose: hostname of the DB server for `wp-config.php` (useful for custom hostnames).

- `DOMAIN_NAME`
  - Defined: not defined by default; optional (can be provided in `.env`)
  - Used: `srcs/requirements/nginx/tools/setup.sh`
  - Container: `nginx`
  - Purpose: Common Name (CN) for generated TLS certificate; allows certificate CN matching the evaluator domain.

- `USER`
  - Defined: host environment variable (shell login name)
  - Used: `srcs/docker-compose.yml` in volume `device` paths `/home/${USER}/data/...`
  - Purpose: resolve the host path where named volumes are mapped under `/home/<login>/data` as required by the subject.

---

## 3) Where variables are defined and consumed

- `srcs/.env` is loaded into services via `env_file: - .env` in `srcs/docker-compose.yml` for `mariadb`, `wordpress`, and `nginx`.
- Shell variables like `USER` are expanded by Docker Compose at parse time from the process environment where `docker compose` runs.
- The scripts inside containers (setup scripts) read environment variables from their process environment (which originates from Compose using `env_file`).

---

## 4) Role of environment variables in Docker Compose

- `env_file` entries instruct Compose to load key=value pairs from a file and pass them to the container at runtime as environment variables.
- Environment variables are the standard mechanism to provide configuration and secrets to containers without baking them into images.
- Compose performs variable substitution of `${VAR}` in the compose file using the shell environment or `.env` file located next to the compose file.

---

## 5) Hardcoded values vs environment variables vs Docker secrets

- Hardcoded values:
  - Values written directly in Dockerfiles or tracked source files (e.g., passwords in a Dockerfile) are insecure and forbidden by subject.
  - This project has no hardcoded passwords in Dockerfiles.

- Environment variables:
  - Convenient for configuration; passed via `.env` or `env_file` in Compose.
  - In this repo, `srcs/.env` provides DB credentials used by services.
  - `.env` is committed in this workspace; subject warns that credentials in repo will cause failure. For evaluation you must ensure secrets are handled per subject guidance.

- Docker secrets:
  - More secure for sensitive values in production; not required by mandatory subject, but recommended.
  - Docker secrets are not currently used in this project.

---

## 6) Comparison with Mandatory requirements

✅ Correct implementations
- No passwords are present in Dockerfiles. ✅
- Variables are supplied via `.env` and consumed by services via `env_file`. ✅
- `docker-compose.yml` uses `env_file` rather than embedding credentials in the compose file. ✅
- `USER` host substitution is used to map volumes into `/home/<login>/data`, satisfying subject host-path requirement. ✅

⚠ Possible problems
- `srcs/.env` currently contains plaintext credentials and appears committed. The subject states any credentials found in Git repo will result in project failure; you should not commit secrets. ⚠
- `DOMAIN_NAME` and `DB_HOST` are optional but may need to be set for evaluator environment. ⚠
- No Docker secrets are used (recommended but optional). ⚠

❌ Missing requirements
- Use of Docker secrets is not mandatory, so this is not strictly missing. However, the committed `.env` with real credentials is a compliance risk and should be addressed. ❌ (risk)

---

## 7) Verification checks (how to confirm variables work)

1. Confirm `.env` is loaded by Compose for services:
```bash
cd srcs
docker compose config --env-file .env | sed -n '1,200p'
```
Look for environment entries under each service.

2. Inside MariaDB container, verify root password was applied:
```bash
docker compose exec mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e 'SELECT 1;'
```

3. Inside WordPress container, verify `wp-config.php` contains DB constants set from env:
```bash
docker compose exec wordpress sed -n '1,80p' /var/www/html/wp-config.php
```

4. Verify `USER` substitution resolves to the host login (used by Compose):
```bash
echo $USER
# and verify host path exists: ls -la /home/$USER/data/mariadb
```

---

## 8) Security recommendations (mandatory-focused)

- Do NOT commit real credentials into the Git repository. If `.env` contains secrets, remove it from the repo and add it to `.gitignore`.
- Prefer Docker secrets for sensitive values when possible (subject recommends secrets as optional improvement).
- Ensure `.env` used for evaluation contains the required variables but avoid pushing it publicly.

---

## 9) Common 42 evaluation Q&A (env vars)

Q: Are passwords allowed in Dockerfiles?
A: No. The subject explicitly forbids passwords in Dockerfiles.

Q: Where should I place environment variables?
A: Use `.env` loaded via `env_file` in `docker-compose.yml` or Docker secrets for sensitive data.

Q: Does Compose automatically replace `${USER}`?
A: Compose fallback resolves `${VAR}` from the shell environment where `docker compose` runs.

Q: How do I prove that services received the variables?
A: Inspect container environment or generated configuration (e.g., `wp-config.php` or MariaDB initialized users).

---

## 10) Files changed/created by this analysis

- Added: `docs/environment_variables.md` (this file)

No runtime files were changed for this task.

---

## 11) How to remove sensitive `.env` from git history (if you want to fix now)

If `.env` was committed, remove and ensure `.gitignore` contains it. Example (careful — history rewrite):
```bash
git rm --cached srcs/.env
echo "srcs/.env" >> .gitignore
git commit -m "Remove committed .env from repo and ignore it"
```
For complete history removal use `git filter-branch` or `git filter-repo` (more advanced).

---

End of document.
