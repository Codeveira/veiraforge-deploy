#!/bin/sh
# Pulls every secret this compose file reads via ${VAR} (POSTGRES_PASSWORD,
# VEIRAFORGE_MASTER_KEY, VEIRAFORGE_GITHUB_WEBHOOK_SECRET,
# VEIRAFORGE_GITLAB_WEBHOOK_SECRET, VEIRAFORGE_GITEA_WEBHOOK_SECRET) out of a
# Veira Seal environment into ./.env, which `docker compose up` loads
# automatically from this directory -- no docker-compose.yml change needed,
# since it already reads these as ${VAR:-...}/${VAR:?...} rather than
# hardcoding them (OPEN-QUESTIONS.md #6, IDEAS.md §5f).
#
# This is one option among others, never required: set the same variables
# any other way (shell env, a hand-written .env, a different secret
# manager) and this script is unnecessary.
#
# Usage: ./pull-secrets.sh PROJECT/ENV [-addr URL] [veira pull flags...]
#
# Example, after `veira set veiraforge/production POSTGRES_PASSWORD=... \
#   VEIRAFORGE_MASTER_KEY=... VEIRAFORGE_GITHUB_WEBHOOK_SECRET=...`:
#   ./pull-secrets.sh veiraforge/production -addr https://veira.internal:8200
#   docker compose up -d
set -eu

if [ "$#" -lt 1 ]; then
	echo "usage: $0 PROJECT/ENV [veira pull flags...]" >&2
	exit 2
fi

if ! command -v veira >/dev/null 2>&1; then
	echo "$0: 'veira' CLI not found on PATH -- install Veira Seal's client, or set these variables another way (see docker-compose.yml's top comment)" >&2
	exit 1
fi

project_env="$1"
shift

dir="$(dirname "$0")"
veira pull "$project_env" -format env -o "$dir/.env" "$@"
echo "wrote $dir/.env -- run 'docker compose up' from $dir now" >&2
