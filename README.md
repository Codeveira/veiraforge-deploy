# veiraforge-deploy

Runs [VeiraForge](https://veiraforge.com), self-hosted CI/CD, with Docker
Compose: Postgres, the server (webhooks, dashboard, API) and a worker that
runs the pipelines.

```sh
cp .env.example .env   # fill it in: each setting is explained there
make doctor            # checks .env and this host, changes nothing
make up-release        # starts the images published to ghcr.io (IMAGE_TAG)
make user-create EMAIL=you@example.com PASSWORD='a long password'
```

`make up` builds the images from a `../veiraforge` checkout instead. The
dashboard listens on `127.0.0.1:8400`; put a reverse proxy with HTTPS in
front of it.

| Command | What it does |
|---|---|
| `make doctor` | checks `.env`, Docker and the published images |
| `make up-release` / `make deploy-release` | start / move to the published images of `IMAGE_TAG` |
| `make up` / `make deploy` | the same, building from `../veiraforge` |
| `make ps`, `make logs` | how the services are doing (`SERVICE=worker make logs`) |
| `make backup` | dumps the database to `./backup` |
| `make psql` | a psql shell on the bundled Postgres |
| `make help` | every target |

Steps in their own container images (`image:`, `services:`) need the
overlay in `docker-compose.containers.yml`; read it first, it hands the
worker the Docker socket.

The full guide, with webhooks for every platform, upgrades and backups:
<https://veiraforge.com/docs/install/>.
