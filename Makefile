.PHONY: help build pull up down restart ps logs deploy upgrade backup clean config psql user-create project-create

COMPOSE := docker compose
SERVICE ?= veiraforge
BACKUP_DIR ?= ./backup

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort

build: ## Build the veiraforge/worker images from ../veiraforge (does not touch postgres)
	$(COMPOSE) build veiraforge worker

pull: ## Pull the base images this stack doesn't build itself (postgres only)
	$(COMPOSE) pull postgres

up: ## Start the stack, building veiraforge/worker from source first (never a stale/absent ghcr.io pull)
	$(MAKE) build
	$(COMPOSE) up -d

down: ## Stop the stack
	$(COMPOSE) down

restart: ## Restart all services in place
	$(COMPOSE) restart

ps: ## Show service status
	$(COMPOSE) ps

logs: ## Tail logs; SERVICE=worker make logs for one service, default is all
	$(COMPOSE) logs -f --tail=200 $(SERVICE)

deploy: ## Rebuild veiraforge/worker from source and recreate only what changed
	$(MAKE) build
	$(COMPOSE) up -d --no-deps veiraforge worker

upgrade: deploy ## Alias for deploy (kept for anyone used to `make upgrade` from the other repos)

config: ## Validate docker-compose.yml and the resolved .env substitutions, without starting anything
	$(COMPOSE) config -q

backup: ## Dump the Postgres database to $(BACKUP_DIR)/veiraforge-<timestamp>.sql (local only, never off-box)
	mkdir -p $(BACKUP_DIR)
	$(COMPOSE) exec -T postgres pg_dump -U veiraforge veiraforge > $(BACKUP_DIR)/veiraforge-$$(date +%Y%m%d%H%M%S).sql

clean: ## Stop the stack and remove its containers, networks and orphans (keeps the postgres-data volume)
	$(COMPOSE) down --remove-orphans

psql: ## Open a psql shell on the bundled Postgres
	$(COMPOSE) exec postgres psql -U veiraforge veiraforge

user-create: ## Bootstrap a dashboard login: make user-create EMAIL=... PASSWORD=...
	$(COMPOSE) exec veiraforge /veiraforge user create -email "$(EMAIL)" -password "$(PASSWORD)"

project-create: ## Register a project: make project-create NAME=... PLATFORM=... REPO=owner/repo [CLONE_URL=...]
	$(COMPOSE) exec veiraforge /veiraforge project create -name "$(NAME)" -platform "$(PLATFORM)" -repo "$(REPO)" $(if $(CLONE_URL),-clone-url "$(CLONE_URL)")
