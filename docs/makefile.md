# Makefile analysis for Inception (Mandatory only)

## Scope
This document analyzes only the **Mandatory** requirements of the official 42 Inception subject, and only the project Makefile.

---

## 1) Purpose of the Makefile

The Makefile is the root automation entrypoint for the project.
Its role is to:

- Launch the full infrastructure using Docker Compose.
- Ensure images are built from your local Dockerfiles.
- Provide simple lifecycle commands (up/down/start/stop/re).
- Prepare host persistence directories required by the volume configuration.

This directly matches the mandatory subject requirement that a Makefile at repository root must set up the entire application and build images using `docker-compose.yml`.

---

## 2) Mandatory subject requirements relevant to Makefile

From the official subject (mandatory-relevant excerpts):

- “A Makefile is also required and must be located at the root of your directory. It must set up your entire application (i.e., it has to build the Docker images using docker-compose.yml).”
- “You have to use docker compose.”
- “The Dockerfiles must be called in your docker-compose.yml by your Makefile.”

How this project now satisfies these points:

- Makefile exists at repository root.
- The default target starts the whole stack through Docker Compose.
- The `up` target uses `docker compose ... up --build`, so images are built from local Dockerfiles referenced by `srcs/docker-compose.yml`.

---

## 3) Initial state assessment (before edit)

### Previous implementation state
- The Makefile existed but was empty.

### Compliance check before edit
- Root Makefile exists: **partially correct** (file present, but no logic).
- “Must set up entire application”: **not satisfied**.
- “Must build Docker images using docker-compose.yml”: **not satisfied**.

### Why modification was required
Without commands/targets, the Makefile could not orchestrate infrastructure setup and could not satisfy mandatory requirements.

---

## 4) Current Makefile (after required minimal edit)

```make
COMPOSE_FILE = ./srcs/docker-compose.yml
COMPOSE_CMD = docker compose -f $(COMPOSE_FILE)

DATA_DIR = /home/$(USER)/data
DB_DATA_DIR = $(DATA_DIR)/mariadb
WP_DATA_DIR = $(DATA_DIR)/wordpress

all: up

up: data_dirs
	$(COMPOSE_CMD) up --build -d

down:
	$(COMPOSE_CMD) down

start:
	$(COMPOSE_CMD) start

stop:
	$(COMPOSE_CMD) stop

data_dirs:
	mkdir -p $(DB_DATA_DIR) $(WP_DATA_DIR)

re: down up

.PHONY: all up down start stop data_dirs re
```

---

## 5) Line-by-line explanation (every line)

### Line 1
`COMPOSE_FILE = ./srcs/docker-compose.yml`
- Defines the Compose definition file path used by all commands.
- Keeps the path centralized to avoid duplication and mistakes.

### Line 2
`COMPOSE_CMD = docker compose -f $(COMPOSE_FILE)`
- Creates a reusable command prefix for Docker Compose.
- Forces all targets to use the same compose file.

### Line 3
(blank line)
- Visual separation between Compose configuration and data path configuration.

### Line 4
`DATA_DIR = /home/$(USER)/data`
- Host base directory for persistent data.
- Uses shell `USER` environment variable so path matches current login.

### Line 5
`DB_DATA_DIR = $(DATA_DIR)/mariadb`
- Host directory where MariaDB persistent data will be stored.

### Line 6
`WP_DATA_DIR = $(DATA_DIR)/wordpress`
- Host directory where WordPress persistent files will be stored.

### Line 7
(blank line)
- Visual separation before targets.

### Line 8
`all: up`
- Default target.
- Running `make` triggers `up`.
- This provides the “set up entire application” behavior directly.

### Line 9
(blank line)
- Readability spacing.

### Line 10
`up: data_dirs`
- Declares `up` depends on `data_dirs`.
- Ensures host bind paths exist before container startup.

### Line 11
`$(COMPOSE_CMD) up --build -d`
- Starts all services defined in compose file.
- `--build`: builds images before start, satisfying mandatory build requirement.
- `-d`: detached mode.

### Line 12
(blank line)
- Readability spacing.

### Line 13
`down:`
- Target to stop and remove stack resources managed by Compose (containers/network).

### Line 14
`$(COMPOSE_CMD) down`
- Executes stack shutdown/teardown while preserving named volumes unless explicitly removed.

### Line 15
(blank line)
- Readability spacing.

### Line 16
`start:`
- Target to start already created stopped containers.

### Line 17
`$(COMPOSE_CMD) start`
- Restarts existing containers without recreating them.

### Line 18
(blank line)
- Readability spacing.

### Line 19
`stop:`
- Target to stop running containers without removing them.

### Line 20
`$(COMPOSE_CMD) stop`
- Gracefully stops stack services.

### Line 21
(blank line)
- Readability spacing.

### Line 22
`data_dirs:`
- Helper target to prepare host persistence directories.

### Line 23
`mkdir -p $(DB_DATA_DIR) $(WP_DATA_DIR)`
- Creates required host paths if they do not exist.
- `-p` makes command idempotent (safe to run repeatedly).

### Line 24
(blank line)
- Readability spacing.

### Line 25
`re: down up`
- Rebuild/restart convenience target.
- Runs full stop then start sequence.

### Line 26
(blank line)
- Readability spacing.

### Line 27
`.PHONY: all up down start stop data_dirs re`
- Declares logical targets, not files.
- Prevents false “up-to-date” behavior if files with same names appear.

---

## 6) Explanation of every target

### `all`
- Default entrypoint.
- Delegates to `up`.

### `up`
- Prepares host volume directories.
- Builds images and starts full infrastructure.
- This is the key mandatory target behavior.

### `down`
- Stops and removes running stack objects created by Compose.

### `start`
- Starts existing stopped containers.

### `stop`
- Stops running containers while keeping them created.

### `data_dirs`
- Creates host directories used by volume bind devices.

### `re`
- Convenience rebuild/restart flow (`down` then `up`).

---

## 7) Why each command is used

- `docker compose -f ./srcs/docker-compose.yml ...`
  - Ensures orchestration is done via the project compose file in `srcs`.
  - Complies with mandatory “use docker compose”.

- `up --build -d`
  - `up`: starts entire application.
  - `--build`: builds images from local Dockerfiles (mandatory).
  - `-d`: background execution for normal workflow.

- `down`
  - Cleanly tears down stack runtime.

- `start` / `stop`
  - Lightweight lifecycle controls for already-created containers.

- `mkdir -p`
  - Guarantees required host persistence directories exist.

---

## 8) How the Makefile interacts with Docker Compose

Flow:

1. `make` invokes `all`.
2. `all` invokes `up`.
3. `up` first invokes `data_dirs` to create `/home/$USER/data/mariadb` and `/home/$USER/data/wordpress`.
4. `up` then runs `docker compose -f ./srcs/docker-compose.yml up --build -d`.
5. Compose reads service definitions, builds images from local Dockerfiles, creates network/volumes, and starts containers.

This makes the Makefile the stable root command surface while Compose handles orchestration internals.

---

## 9) Mandatory compliance status

### Correct implementations

- Root Makefile exists and is now functional.
- Makefile sets up the full app stack through Docker Compose.
- Images are built using compose file via `--build`.
- Compose file path points to `srcs/docker-compose.yml` consistent with expected structure.

### Incorrect implementations

- None in current Makefile for mandatory scope.

### Missing requirements (Makefile scope only)

- None currently missing in Makefile scope.

(Other mandatory checks exist in Dockerfiles, compose service definitions, TLS/NGINX config, and environment handling, but those are outside this file’s scope.)

---

## 10) Minimal-change policy followed

- The Makefile was empty, so changes were necessary.
- Only mandatory-supporting targets were added.
- Existing repository architecture was preserved.
- No bonus service or bonus feature was introduced.

---

## 11) Final conclusion

The Makefile now fulfills the mandatory role required by the official Inception subject:

- Located at repository root.
- Uses Docker Compose.
- Sets up the full infrastructure.
- Builds images using `srcs/docker-compose.yml`.
