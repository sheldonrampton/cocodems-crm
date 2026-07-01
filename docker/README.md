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
docker compose --project-directory . -f docker/docker-compose.yml up --build
```

First boot downloads WordPress and CiviCRM into the image, waits for MariaDB, and runs the installer. This can take several minutes.

When startup completes, open:

| URL | Purpose |
|-----|---------|
| http://localhost:8080 | WordPress front page |
| http://localhost:8080/wp-admin | WordPress admin |
| http://localhost:8080/wp-admin/admin.php?page=CiviCRM | CiviCRM |

Log in with `CIVICRM_ADMIN_USER` and `CIVICRM_ADMIN_PASS` from `.env` (default user: `admin`).

## Common commands

```bash
# Start in the background
docker compose --project-directory . -f docker/docker-compose.yml up -d --build

# Follow logs
docker compose --project-directory . -f docker/docker-compose.yml logs -f

# Stop containers (keep data)
docker compose --project-directory . -f docker/docker-compose.yml down

# Stop and remove database + WordPress volumes (fresh install)
docker compose --project-directory . -f docker/docker-compose.yml down -v

# WP-CLI
docker compose --project-directory . -f docker/docker-compose.yml exec php wp plugin list --allow-root --path=/var/www/html

# CiviCRM CLI (run as www-data)
docker compose --project-directory . -f docker/docker-compose.yml exec -u www-data php cv api4 Contact.get -limit 5
```

## Services

| Service | Image / build | Role |
|---------|---------------|------|
| `nginx` | `nginx:1.27-alpine` | HTTP reverse proxy to PHP-FPM |
| `php` | `docker/php/Dockerfile` | WordPress + CiviCRM on PHP 8.2 FPM |
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

## Troubleshooting

**Installer fails or times out waiting for MariaDB**

Wait for the `mariadb` health check to pass, then restart PHP:

```bash
docker compose --project-directory . -f docker/docker-compose.yml restart php
```

**Fresh reinstall**

```bash
docker compose --project-directory . -f docker/docker-compose.yml down -v
docker compose --project-directory . -f docker/docker-compose.yml up --build
```

**Port 8080 already in use**

Set `HTTP_PORT` in `.env` (e.g. `8081`) and update `CIVICRM_UF_BASEURL` to match.

## Production

This Compose file is for **local development only**. Production deployment uses Terraform on AWS EC2 — see [architecture.md](../docs/architecture.md) and [ADR-0004](../docs/adr/0004-aws-ec2.md).
