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
│   └── setup-staging-auth.sh
│
├── backups/                       # (planned) Local backup storage (gitignored)
│
├── tests/                         # (planned) Automated tests
│
└── .github/                       # (planned) CI/CD and GitHub templates
    ├── workflows/
    │   ├── ci.yml
    │   ├── deploy-staging.yml
    │   └── deploy-production.yml
    │
    ├── ISSUE_TEMPLATE/
    └── pull_request_template.md
```
