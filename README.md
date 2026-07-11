# CoCoDems CRM

This project aims to build an open-source CRM platform for county Democratic parties using WordPress and CiviCRM. Columbia County Democrats (Columbia County, Wisconsin) will serve as the prototype. The long-term goal is a reusable platform that integrates volunteer management, email, donations, events, and websites while interoperating with NGP VAN and Action Network.

# Getting started

## Local development

```bash
cp .env.example .env   # set passwords in .env
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.local.yml up --build
```

Open http://localhost:8080 when startup completes. WordPress and CiviCRM are installed automatically on first boot.

Log in at **http://localhost:8080/wp-login.php** using `CIVICRM_ADMIN_USER` and `CIVICRM_ADMIN_PASS` from your `.env` file (defaults: `admin` / `change-me`).

See [docker/README.md](docker/README.md) for details, troubleshooting, and common commands.

## Continuous integration

Pull requests run [GitHub Actions](.github/workflows/ci.yml): PHP lint (PHPCS), PHPUnit, ShellCheck, Terraform format/validate, and Docker Compose config checks.

Install Composer once (macOS with Homebrew):

```bash
brew install composer
```

Then from the repo root:

```bash
composer install
composer run lint:php   # WordPress coding standards
composer run test       # PHPUnit smoke tests
```

No local Composer install? Use Docker instead:

```bash
docker run --rm -v "$(pwd):/app" -w /app composer:2 install
docker run --rm -v "$(pwd):/app" -w /app composer:2 run lint:php
docker run --rm -v "$(pwd):/app" -w /app composer:2 run test
```

## Staging deployment

Staging runs on AWS EC2 (Terraform + deploy scripts). See [docs/deployment.md](docs/deployment.md) for the full runbook.

Quick sequence after `terraform apply`:

1. SSM into the instance (`--region us-east-2`)
2. `bootstrap-staging-server.sh` → copy `.env.staging.example` to `.env` → `deploy-staging.sh`
3. `setup-staging-tls.sh` (HTTPS + CiviCRM URL sync)

# Contributing

## Workflow

Use a **branch and pull request** for most changes:

```bash
git checkout main
git pull
git checkout -b fix/short-description   # or feature/..., docs/...
# edit, then run local checks (below)
git add .
git commit -m "Explain why this change is needed"
git push -u origin fix/short-description
```

Open a pull request on GitHub. [CI](.github/workflows/ci.yml) runs automatically. Merge when checks pass and the change looks right.

**Direct commits to `main`** are possible and also trigger CI, but prefer branches and PRs for anything that touches PHP, Terraform, Docker, or deploy scripts. One focused change per PR is easier to review and revert.

## Before you push

Run the same checks CI uses (see [Continuous integration](#continuous-integration) above):

```bash
composer run lint:php
composer run test
```

For infrastructure or script changes, also run when you can:

```bash
terraform fmt -check -recursive infra/terraform
shellcheck -S error scripts/*.sh   # requires shellcheck
```

Follow [docs/coding-standards.md](docs/coding-standards.md). Record non-obvious architectural choices in [docs/adr/](docs/adr/).

## What not to commit

Never commit secrets or environment-specific data:

* `.env` files (use `.env.example` / `.env.staging.example` as templates)
* Database dumps, backups, or `wordpress/wp-content/uploads/`
* TLS keys, API tokens, or `*.pem` files

## After merge

Automated staging deploy is not wired up yet (`deploy-staging.yml` is planned). After merging to `main`, update staging manually on the server:

```bash
cd /opt/cocodems-crm
git pull
sudo -u ubuntu bash scripts/deploy-staging.sh
```

See [docs/deployment.md](docs/deployment.md) for TLS, CiviCRM upgrades, and troubleshooting.

# Repository Structure

The tree below shows the target layout. Directories and files marked **(planned)** are not in the repository yet. See [roadmap.md](docs/roadmap.md) for when each is expected.

```text
cocodems-crm/
│
├── README.md                      # Project overview and getting started
├── LICENSE                        # (planned) Open-source license
├── .gitignore
├── .env.example                   # Sample environment variables
│
├── docs/                          # Project documentation
│   ├── vision.md
│   ├── architecture.md
│   ├── roadmap.md
│   ├── data-model.md
│   ├── deployment.md              # Staging deploy runbook
│   ├── coding-standards.md
│   └── adr/                       # Architecture Decision Records (ADRs)
│
├── infra/                         # Infrastructure as Code
│   └── terraform/                 # AWS staging (production planned)
│       ├── environments/
│       │   ├── staging/           # Staging environment
│       │   └── production/        # (planned)
│       ├── modules/
│       └── README.md
│
├── docker/                        # Local development environment
│   ├── docker-compose.yml
│   ├── nginx/
│   ├── php/
│   └── mariadb/
│
├── wordpress/                     # Custom WordPress code (core installed by Docker)
│   ├── wp-content/
│   │   ├── themes/
│   │   │   └── cocodems-theme/
│   │   │
│   │   ├── plugins/
│   │   │   └── cocodems-custom/
│   │   │
│   │   └── mu-plugins/            # (planned)
│   │
│   └── README.md
│
├── scripts/                       # Deploy and ops scripts
│   ├── bootstrap-staging-server.sh
│   ├── deploy-staging.sh
│   ├── setup-staging-tls.sh
│   ├── setup-staging-auth.sh
│   ├── fix-civicrm-urls.sh        # After TLS or domain changes
│   ├── diagnose-civicrm-urls.sh
│   ├── upgrade-civicrm.sh         # After bumping CIVICRM_VERSION
│   ├── backup-db.sh               # MariaDB dump (optional S3 upload)
│   ├── restore-db.sh              # Restore from local file or s3://
│   ├── cron-backup-db.sh          # Cron entrypoint (docker group wrapper)
│   └── setup-staging-backup-cron.sh
│
├── backups/                       # Local backup storage (gitignored)
│
├── tests/                         # PHPUnit smoke tests
│
└── .github/                       # GitHub Actions and templates
    ├── workflows/
    │   ├── ci.yml                 # Lint and test on pull requests
    │   ├── deploy-staging.yml     # (planned)
    │   └── deploy-production.yml  # (planned)
    │
    ├── ISSUE_TEMPLATE/
    └── pull_request_template.md
```
