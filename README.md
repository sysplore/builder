# Frappe Builder Docker Image

A standalone, ready-to-run [Frappe Builder](https://github.com/frappe/builder) Docker image, built and maintained for simple, predictable deployment.

We build and publish the image, so you don't have to. Copy the `docker-compose.yml`, tweak a few config values, and run `docker compose up -d`. No guessing, no worries.

## What's inside

- **Frappe** (core framework) — `version-16` branch
- **Builder** — the latest `master` release of [frappe/builder](https://github.com/frappe/builder)

The image is built with the official [frappe_docker](https://github.com/frappe/frappe_docker) layered image so it stays lean and follows the upstream conventions.

The published image is `mitexleo/sysplore-builder` on [Docker Hub](https://hub.docker.com/r/mitexleo/sysplore-builder).

## Deploy

### Prerequisites

- Docker with the Compose plugin (`docker compose version`)
- ~4 GB free RAM and ~10 GB disk

### Quick start

1. Copy the `docker-compose.yml` from this repository to your server.

2. Create your `.env` from the example:

   ```bash
   cp example.env .env
   ```

   Change the config values you care about (see [Configuration](#configuration) below).

3. Start the stack:

   ```bash
   docker compose up -d
   ```

4. Wait for the first-time site creation to finish, then open:

   ```text
   http://<your-server>:8080
   ```

   Login with the administrator email `Administrator` and the password you set via `SITE_ADMIN_PASSWORD` (default: `admin`).

### Configuration

The compose file is pre-configured to work out of the box. Everything that commonly changes is set via `.env` (copied from `example.env`) and has a sane default:

| Variable | Default | Purpose |
| --- | --- | --- |
| `BUILDER_IMAGE` | `mitexleo/sysplore-builder` | Image to run |
| `BUILDER_TAG` | `latest` | Image tag (pin to a version for reproducible deploys) |
| `DB_PASSWORD` | `admin` | MariaDB root password — **change this in production** |
| `SITE_NAME` | `frontend` | Frappe site name (used internally) |
| `SITE_ADMIN_PASSWORD` | `admin` | Administrator login password — **change this in production** |
| `HTTP_PUBLISH_PORT` | `8080` | Host port the site is published on |
| `FRAPPE_SITE_NAME_HEADER` | `$$host` | Site name resolved by host header |
| `DEVELOPER_MODE` | `0` | Set to `1` for development |
| `SERVER_SCRIPT_ENABLED` | `1` | Enables server-side scripts in Frappe |
| `GUNICORN_THREADS` / `GUNICORN_WORKERS` / `GUNICORN_TIMEOUT` | `4` / `2` / `120` | Web server concurrency and timeouts |
| `UPSTREAM_REAL_IP_*` | internal defaults | Client IP handling behind proxies |
| `PROXY_READ_TIMEOUT` | `120` | nginx proxy read timeout |
| `CLIENT_MAX_BODY_SIZE` | `50m` | Max upload body size (raise alongside the app's upload limit) |

The `example.env` file documents every variable with explanations, so copy it, tweak, and run.

### What happens on first run

1. `db` starts MariaDB.
2. `configurator` writes `sites/common_site_config.json` from the environment.
3. `create-site` creates the site (`SITE_NAME`) and installs the `builder` app — this only runs once; it skips if the site already exists.
4. `backend`, `frontend`, `websocket`, `scheduler`, and the workers start.

Data lives in Docker named volumes (`sites`, `db-data`, `redis-queue-data`, `logs`), so it survives container restarts and image updates.

### Updating

```bash
docker compose pull
docker compose up -d
```

The site data is preserved in the named volumes; only the application code updates.

## How the image is built

This repository builds and publishes the image automatically with GitHub Actions.

### Apps

`apps.json` declares which Frappe apps the image contains:

```json
[
  {
    "url": "https://github.com/frappe/builder",
    "branch": "master"
  }
]
```

`frappe/frappe` (`version-16`) is always included as the framework.

### Build triggers

- **Scheduled** — every 6 hours the workflow checks the tracked branches for new commits.
- **Manual** — use the *Run workflow* button in the Actions tab, optionally with **force_build** to rebuild even when nothing changed.

### Versioning

- `VERSION` holds the current image version (semantic, e.g. `1.0.0`).
- `REPO_VERSIONS.json` records the exact commit SHA of each tracked repository in the last build.
- When any tracked repo changes, the workflow:
  1. bumps the patch version in `VERSION`,
  2. rebuilds the image,
  3. pushes it to Docker Hub as both `mitexleo/sysplore-builder:<version>` and `mitexleo/sysplore-builder:latest`.

### Build process

1. Clones [frappe_docker](https://github.com/frappe/frappe_docker).
2. Runs its `images/layered/Containerfile` with:
   - `FRAPPE_BRANCH=version-16` for the framework,
   - `apps.json` (from this repo) passed as a BuildKit secret so the Builder app is installed during `bench init`.
3. Pushes the result to Docker Hub.

## Development

### Prerequisites

- Docker Engine v23+ (for BuildKit secrets)
- `jq` and `curl` for local testing

### Build the image locally

```bash
git clone https://github.com/frappe/frappe_docker
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --secret=id=apps_json,src=apps.json \
  --tag=local-sysplore-builder:test \
  --file=frappe_docker/images/layered/Containerfile .
```

### Required GitHub secrets

The workflow publishes to Docker Hub, so the repository needs these secrets:

- `DOCKER_USERNAME` — Docker Hub username
- `DOCKER_PASSWORD` — Docker Hub password or access token

## License

MIT — see [LICENSE](LICENSE). Frappe and Builder remain under their own licenses.
