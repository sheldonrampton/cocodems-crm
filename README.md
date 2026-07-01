# CoCoDems CRM

This project aims to build an open-source CRM platform for county Democratic parties using WordPress and CiviCRM. Columbia County Democrats (Columbia County, Wisconsin) will serve as the prototype. The long-term goal is a reusable platform that integrates volunteer management, email, donations, events, and websites while interoperating with NGP VAN and Action Network.

# Getting started

## Local development

```bash
cp .env.example .env   # set passwords in .env
docker compose --project-directory . -f docker/docker-compose.yml up --build
```

Open http://localhost:8080 when startup completes. WordPress and CiviCRM are installed automatically on first boot. See [docker/README.md](docker/README.md) for details.

# Repository Structure

```text
cocodems-crm/
│
├── README.md                      # Project overview and getting started
├── LICENSE                        # Open-source license (TBD)
├── .gitignore
├── .env.example                   # Sample environment variables
│
├── docs/                          # Project documentation
│   ├── vision.md                  # Project goals and guiding principles
│   ├── architecture.md            # System architecture
│   ├── roadmap.md                 # Development roadmap and milestones
│   ├── data-model.md              # CRM entities and relationships
│   ├── deployment.md              # Deployment procedures
│   ├── coding-standards.md        # Coding conventions
│   └── adr/                       # Architecture Decision Records (ADRs)
│
├── infra/                         # Infrastructure as Code
│   └── terraform/
│       ├── environments/
│       │   ├── staging/
│       │   └── production/
│       ├── modules/
│       └── README.md
│
├── docker/                        # Local development environment
│   ├── docker-compose.yml
│   ├── nginx/
│   ├── php/
│   └── mariadb/
│
├── wordpress/                     # WordPress-related code
│   ├── wp-content/
│   │   ├── themes/
│   │   │   └── cocodems-theme/
│   │   │
│   │   ├── plugins/
│   │   │   └── cocodems-custom/
│   │   │
│   │   └── mu-plugins/
│   │
│   └── README.md
│
├── scripts/                       # Utility scripts
│   ├── backup-db.sh
│   ├── restore-db.sh
│   ├── deploy-staging.sh
│   ├── deploy-production.sh
│   └── sync-production-to-staging.sh
│
├── backups/                       # Optional local backup storage (ignored by Git)
│
├── tests/                         # Automated tests
│
└── .github/
    ├── workflows/
    │   ├── ci.yml
    │   ├── deploy-staging.yml
    │   └── deploy-production.yml
    │
    ├── ISSUE_TEMPLATE/
    └── pull_request_template.md
```
