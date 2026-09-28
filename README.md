# Frappe Builder Docker Image

A standalone, ready-to-run [Frappe Builder](https://github.com/frappe/builder) Docker image, built and maintained for simple, predictable deployment.

We build and publish the image, so you don't have to. Copy the `docker-compose.yml`, tweak a few config values, and run `docker compose up -d`. No guessing, no worries.

## What's inside

Two image lines are published from this repository, both on the **Frappe `version-16`** framework:

- **`stable`** — Builder **`master`** (released) — recommended for production
- **`latest`** / **`edge`** — Builder **`develop`** (newest features, unreleased, moves frequently)

The images are built with the official [frappe_docker](https://github.com/frappe/frappe_docker) layered build so they stay lean and follow upstream conventions.

The published images are on [Docker Hub](https://hub.docker.com/r/mitexleo/sysplore-builder) as `mitexleo/sysplore-builder`.

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
| `BUILDER_TAG` | `stable` | Image tag: `stable`, `latest`/`edge`, or a pinned version |
| `DB_PASSWORD` | `admin` | MariaDB root password — **change this in production** |
| `SITE_NAME` | `frontend` | Frappe site name (used internally) |
| `SITE_ADMIN_PASSWORD` | `admin` | Administrator login password — **change this in production** |
| `HTTP_PUBLISH_PORT` | `8080` | Host port the site is published on |
| `FRAPPE_SITE_NAME_HEADER` | `$$host` | Site name resolved by host header |
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

### Choosing a line

Pick the line with `BUILDER_TAG`:

| `BUILDER_TAG` | Line | Source | Tags |
| --- | --- | --- | --- |
| `stable` (default) | Stable | Builder `master` | moving `stable` |
| `latest` / `edge` | Edge | Builder `develop` | moving `latest`, `edge` |
| `1.1.0` | Stable, pinned | Builder `master` | immutable version |
| `edge-1.0.6` | Edge, pinned | Builder `develop` | immutable version |

Suggestions:

- **Production:** use `stable`, or pin a specific version (e.g. `BUILDER_TAG=1.1.0`) so upgrades are deliberate and rollback is trivial.
- **You need an unreleased Builder feature:** use `latest`/`edge`, ideally pinned to a tested `edge-<version>`.
- Each build publishes an immutable version tag, so you can always roll back by setting `BUILDER_TAG` to an earlier one.

Browse available versions on [Docker Hub](https://hub.docker.com/r/mitexleo/sysplore-builder/tags).

## How the images are built

This repository builds and publishes both lines automatically with GitHub Actions.

### Tracks

Each line is defined by a track directory:

```
tracks/
  stable/   Builder master   -> tags: stable,   <version>
  edge/     Builder develop  -> tags: latest, edge, <version>-edge
```

Each track has its own `apps.json`, `VERSION`, and `REPO_VERSIONS.json`:

```json
[
  {
    "url": "https://github.com/frappe/builder",
    "branch": "master"
  }
]
```

`frappe/frappe` (`version-16`) is always included as the framework and is tracked per track in `REPO_VERSIONS.json`.

### Build triggers

- **Scheduled** — every 6 hours the workflow checks each track's branches for new commits.
- **Manual** — use the *Run workflow* button in the Actions tab, optionally with **force_build** to rebuild even when nothing changed.

### Versioning

- `tracks/<track>/VERSION` holds that track's current version (semantic, e.g. `1.0.0`).
- `tracks/<track>/REPO_VERSIONS.json` records the exact commit SHA of each tracked repository in that track's last build.
- When a tracked repo changes in a track, the workflow:
  1. bumps that track's patch version,
  2. rebuilds the image,
  3. pushes it to Docker Hub as its immutable version tag plus its moving tag(s).

The two tracks version independently, and their version tags never collide (`1.1.x` for stable, `edge-1.0.x` for edge). Stable starts at `1.1.0` because the `1.0.x` tags were produced by the earlier single-track (develop) builds.

### Build process

1. Clones [frappe_docker](https://github.com/frappe/frappe_docker).
2. Builds against the `version-16` base images with `FRAPPE_BRANCH=version-16` and the track's `apps.json` passed as a BuildKit secret.
   - **stable** uses frappe_docker's `images/layered/Containerfile` directly.
   - **edge** uses this repo's `Containerfile`, which extends the layered build: it vendors two framework `ui` modules that Builder `develop` imports (`@framework/ui/telemetry` and `@framework/ui/components/TrialBanner`) but that only exist on Frappe's `develop` branch.
3. Pushes the result to Docker Hub.

## Development

### Prerequisites

- Docker Engine v23+ (for BuildKit secrets)
- `jq` and `curl` for local testing

### Build an image locally

The edge track (Builder `develop`):

```bash
git clone --depth 1 https://github.com/frappe/frappe_docker
cp tracks/edge/apps.json frappe_docker/apps.json
cp Containerfile frappe_docker/Containerfile.custom
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --secret=id=apps_json,src=frappe_docker/apps.json \
  --tag=local-sysplore-builder:edge \
  --file=frappe_docker/Containerfile.custom \
  frappe_docker
```

The stable track (Builder `master`) uses the stock layered Containerfile:

```bash
git clone --depth 1 https://github.com/frappe/frappe_docker
cp tracks/stable/apps.json frappe_docker/apps.json
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --secret=id=apps_json,src=frappe_docker/apps.json \
  --tag=local-sysplore-builder:stable \
  --file=frappe_docker/images/layered/Containerfile \
  frappe_docker
```

### Required GitHub secrets

The workflow publishes to Docker Hub, so the repository needs these secrets:

- `DOCKER_USERNAME` — Docker Hub username
- `DOCKER_PASSWORD` — Docker Hub password or access token

## License

MIT — see [LICENSE](LICENSE). Frappe and Builder remain under their own licenses.
