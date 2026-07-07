# Local development environment

Docker Compose runs **Nginx**, **PHP-FPM** (WordPress + CiviCRM), and **MariaDB** for local development.

On first startup the PHP container automatically installs WordPress and CiviCRM. Subsequent starts reuse the persisted database and file volumes.

## Prerequisites

* [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine with Compose v2
* At least 4 GB RAM available to Docker

## Quick start

From the **repository root**:

```bash
cp .env.example .env
```

Edit `.env` and set secure values for `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, and `CIVICRM_ADMIN_PASS`.

Start the stack:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml up --build
```

First boot downloads WordPress and CiviCRM into the image, waits for MariaDB, and runs the installer. This can take several minutes.

When startup completes, open:

| URL | Purpose |
|-----|---------|
| http://localhost:8080 | WordPress front page |
| http://localhost:8080/wp-login.php | **Log in here** (recommended) |
| http://localhost:8080/wp-admin | WordPress admin (redirects to login) |
| http://localhost:8080/wp-admin/admin.php?page=CiviCRM | CiviCRM (after login) |

Log in with `CIVICRM_ADMIN_USER` and `CIVICRM_ADMIN_PASS` from `.env` (default user: `admin`).

Prefer **http://localhost:8080/wp-login.php** over `/wp-admin` — it avoids redirect quirks when Docker maps host port `8080` to Nginx port `80` inside the container.

## Common commands

```bash
# Start in the background
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml up -d --build

# Follow logs
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml logs -f

# Stop containers (keep data)
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml down

# Stop and remove database + WordPress volumes (fresh install)
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml down -v

# WP-CLI
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml exec php wp plugin list --allow-root --path=/var/www/html

# CiviCRM CLI (run as www-data)
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml exec -u www-data php cv api4 Contact.get -limit 5
```

## Services

| Service | Image / build | Role |
|---------|---------------|------|
| `nginx` | `nginx:1.27-alpine` | HTTP reverse proxy to PHP-FPM |
| `php` | `docker/php/Dockerfile` | WordPress + CiviCRM on PHP 8.4 FPM |
| `mariadb` | `mariadb:10.11` | Database for WordPress and CiviCRM |

## Volumes and mounts

| Volume / mount | Contents |
|----------------|----------|
| `wordpress_data` | WordPress core, CiviCRM plugin, uploads |
| `private_config` | `wp-config.php` with database credentials |
| `mariadb_data` | MariaDB data files |
| `../wordpress/wp-content/plugins/cocodems-custom` | Custom plugin (bind mount) |
| `../wordpress/wp-content/themes/cocodems-theme` | Custom theme (bind mount) |

## Configuration

All environment variables are documented in [`.env.example`](../.env.example) at the repository root.

Compose reads `.env` from the repository root. Always pass `--project-directory .` when running from the repo root so variable substitution picks up your `.env` file.

**`HTTP_PORT` and `CIVICRM_UF_BASEURL` must match.** If `HTTP_PORT=8081`, then `CIVICRM_UF_BASEURL` must be `http://localhost:8081`. WordPress stores the site URL at first install; changing the port in `.env` after that will break redirects unless you either:

* run a fresh install: `docker compose ... down -v` then `up --build`, or
* update URLs manually:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml exec php \
  wp option update home 'http://localhost:NEW_PORT' --path=/var/www/html --allow-root
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml exec php \
  wp option update siteurl 'http://localhost:NEW_PORT' --path=/var/www/html --allow-root
```

## Troubleshooting

**`/wp-admin` redirects to `http://localhost/wp-admin/` (missing port)**

Use **http://localhost:8080/wp-login.php** instead. If your browser cached the bad redirect, try a private window or hard refresh (Cmd+Shift+R).

Rebuild/restart Nginx after pulling the latest config if the problem persists:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml restart nginx
```

**MariaDB “not ready yet” loop (attempt N/60…)**

On older PHP images, the MariaDB client required SSL by default while the local MariaDB container does not support it. Pull the latest code and rebuild:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml up --build
```

If the loop continues after rebuild, wait for the `mariadb` health check to pass, then restart PHP:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml restart php
```

**Installer fails or times out waiting for MariaDB**

Wait for the `mariadb` health check to pass, then restart PHP:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml restart php
```

**Fresh reinstall**

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml down -v
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml up --build
```

**Port 8080 already in use**

Set `HTTP_PORT` in `.env` (e.g. `8081`) and set `CIVICRM_UF_BASEURL=http://localhost:8081` to match. If the stack was already installed, run `down -v` and reinstall, or update WordPress URLs manually (see Configuration above).

**Upgrade CiviCRM**

Default version is **6.16.0** (`CIVICRM_VERSION` in `docker/php/Dockerfile`). After changing the version:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml up -d --build
bash scripts/upgrade-civicrm.sh
```

## Production

This Compose file is for **local development only**. Production deployment uses Terraform on AWS EC2 — see [architecture.md](../docs/architecture.md) and [ADR-0004](../docs/adr/0004-aws-ec2.md).
