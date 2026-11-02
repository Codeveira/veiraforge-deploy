#!/usr/bin/env bash
# Checks a VeiraForge deployment's .env and host before `make up` or
# `make up-release`, and says what's wrong: `make doctor`. Changes nothing.
set -u
cd "$(dirname "$0")"

fails=0
warns=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# The value .env gives name, "" if none (the last line wins, like compose).
env_get() {
	[ -f .env ] || return 0
	grep -E "^[[:space:]]*$1=" .env | tail -n 1 | sed -E "s/^[[:space:]]*$1=//; s/^[\"']//; s/[\"']$//"
}

echo "Tools"
if command -v docker >/dev/null 2>&1; then ok "docker: $(docker --version | head -n 1)"; else fail "docker isn't installed"; fi
if docker compose version >/dev/null 2>&1; then ok "docker compose: $(docker compose version --short 2>/dev/null)"; else fail "docker compose (v2) isn't available"; fi
if docker info >/dev/null 2>&1; then ok "the Docker daemon answers"; else fail "the Docker daemon doesn't answer (is it running, and may this user use it?)"; fi

echo ".env"
if [ ! -f .env ]; then
	fail ".env is missing: cp .env.example .env, then fill it in"
else
	ok ".env exists"
	pw="$(env_get POSTGRES_PASSWORD)"
	case "$pw" in
	"") fail "POSTGRES_PASSWORD is empty" ;;
	change-me-before-first-run) fail "POSTGRES_PASSWORD is still the example's" ;;
	*) if [ ${#pw} -lt 12 ]; then warn "POSTGRES_PASSWORD is shorter than 12 characters"; else ok "POSTGRES_PASSWORD is set"; fi ;;
	esac
	key="$(env_get VEIRAFORGE_MASTER_KEY)"
	if [ -z "$key" ]; then
		warn "VEIRAFORGE_MASTER_KEY is empty: deploy tokens and secrets are kept unencrypted (openssl rand -hex 32)"
	elif ! printf '%s' "$key" | grep -Eq '^[0-9a-fA-F]{64}$'; then
		fail "VEIRAFORGE_MASTER_KEY isn't 64 hex characters (openssl rand -hex 32)"
	else
		ok "VEIRAFORGE_MASTER_KEY is set (keep a copy: without it the secrets can't be read)"
	fi
	base="$(env_get VEIRAFORGE_PUBLIC_BASE_URL)"
	case "$base" in
	"") warn "VEIRAFORGE_PUBLIC_BASE_URL is empty: no SSO/OAuth login, and statuses and notifications won't link to runs" ;;
	*/) fail "VEIRAFORGE_PUBLIC_BASE_URL ends in /: leave it out" ;;
	http://*|https://*) ok "VEIRAFORGE_PUBLIC_BASE_URL is $base" ;;
	*) fail "VEIRAFORGE_PUBLIC_BASE_URL isn't an http(s) URL" ;;
	esac
	secrets=0
	for p in GITHUB GITLAB GITEA FORGEJO BITBUCKET BITBUCKET_SERVER AZURE GERRIT SVN; do
		[ -n "$(env_get "VEIRAFORGE_${p}_WEBHOOK_SECRET")" ] && secrets=$((secrets + 1))
	done
	if [ "$secrets" -eq 0 ]; then warn "no VEIRAFORGE_*_WEBHOOK_SECRET is set: no webhook is accepted, runs only start by hand or on a schedule"; else ok "$secrets platform webhook secret(s) set"; fi
	tag="$(env_get IMAGE_TAG)"
	if [ "${tag:-latest}" = latest ]; then warn "IMAGE_TAG is latest: pin a version (e.g. v0.112.0) so an upgrade is a choice"; else ok "IMAGE_TAG is $tag"; fi
fi

files="$(env_get COMPOSE_FILE)"
case "$files" in
*docker-compose.containers.yml*)
	echo "Steps in containers (docker-compose.containers.yml)"
	gid="$(env_get DOCKER_GID)"
	host_gid="$(getent group docker 2>/dev/null | cut -d: -f3)"
	if [ -z "$gid" ]; then
		hint=""
		[ -n "$host_gid" ] && hint=": this host's docker group is $host_gid"
		fail "DOCKER_GID is empty$hint"
	elif [ -n "$host_gid" ] && [ "$gid" != "$host_gid" ]; then
		fail "DOCKER_GID is $gid, but this host's docker group is $host_gid"
	else
		ok "DOCKER_GID is $gid"
	fi
	if [ -S /var/run/docker.sock ]; then ok "/var/run/docker.sock exists"; else fail "/var/run/docker.sock is missing"; fi
	work="$(env_get VEIRAFORGE_WORKER_WORK_DIR)"
	work="${work:-/var/lib/veiraforge/work}"
	if [ ! -d "$work" ]; then
		fail "$work is missing: sudo install -d -o 65532 -g 65532 $work"
	elif [ "$(stat -c %u "$work")" != 65532 ]; then
		fail "$work isn't owned by uid 65532, the worker's: sudo chown 65532:65532 $work"
	else
		ok "$work exists, owned by the worker's user"
	fi
	;;
esac

echo "Compose"
if docker compose config -q >/dev/null 2>&1; then ok "docker-compose.yml and .env resolve"; else fail "docker compose config fails: run it to see why"; fi

if [ -f .env ] && command -v curl >/dev/null 2>&1; then
	echo "Published images (make up-release)"
	tag="$(env_get IMAGE_TAG)"
	tag="${tag:-latest}"
	for name in veiraforge veiraforge-worker; do
		token="$(curl -fsS "https://ghcr.io/token?scope=repository:codeveira/$name:pull" 2>/dev/null | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
		if [ -z "$token" ]; then
			warn "ghcr.io/codeveira/$name isn't public: docker login ghcr.io before make up-release (make up builds it here instead)"
			continue
		fi
		code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" \
			-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
			"https://ghcr.io/v2/codeveira/$name/manifests/$tag")"
		if [ "$code" = 200 ]; then ok "ghcr.io/codeveira/$name:$tag is published"; else fail "ghcr.io/codeveira/$name:$tag isn't there (HTTP $code)"; fi
	done
fi

echo
if [ "$fails" -gt 0 ]; then
	echo "$fails problem(s), $warns warning(s): fix the problems before starting."
	exit 1
fi
echo "No problems, $warns warning(s)."
