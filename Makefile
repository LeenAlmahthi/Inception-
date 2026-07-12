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
