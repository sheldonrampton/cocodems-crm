# Architecture

# CoCoDems CRM Prototype

**Version:** 0.1 (Draft)

## Project Vision

The CoCoDems CRM project is an open-source Customer/Contact Relationship Management platform built for local Democratic Party organizations.

The initial implementation will support the Columbia County (Wisconsin) Democratic Party, but the long-term goal is to develop a reusable platform that can be adopted by other county Democratic parties throughout Wisconsin and potentially elsewhere.

The system should provide a single source of truth for organizational information while integrating with the Democratic Party's existing organizing infrastructure rather than attempting to replace it.

---

# Guiding Principles

## 1. Prefer Configuration over Custom Code

Whenever practical, solve problems using existing CiviCRM and WordPress functionality before writing custom software.

Custom code should only be written when:

* existing functionality cannot accomplish the task
* customization significantly improves usability
* automation reduces ongoing volunteer effort

Every line of custom code becomes a long-term maintenance responsibility.

---

## 2. Keep Custom Code Isolated

Never modify WordPress core.

Never modify CiviCRM core.

Never modify third-party plugins.

Instead:

* create custom WordPress plugins
* create custom themes or child themes
* use CiviCRM extension APIs
* use documented hooks and REST APIs

This allows upstream upgrades without merge conflicts.

---

## 3. Treat Data as the Organization's Most Valuable Asset

The CRM is fundamentally a data management system.

The software can always be replaced.

The data cannot.

Architecture decisions should prioritize:

* data integrity
* data portability
* auditability
* backups
* ownership

The organization should never become locked into proprietary formats.

---

## 4. Build for Volunteers

This system will be maintained primarily by volunteers.

Architectural decisions should optimize for:

* readability
* documentation
* simplicity
* predictable behavior

Avoid clever solutions that future volunteers may struggle to understand.

---

## 5. AI-Friendly Development

The project is intended to be developed using AI-assisted programming.

Documentation is therefore part of the architecture.

Important design decisions should always be documented.

Future AI assistants should be able to understand *why* a decision was made, not merely *what* code currently exists.

---

# High-Level Architecture

```
                    Internet

                        │

                  HTTPS / TLS

                        │

                  Nginx / Apache

                        │

                WordPress Website

                        │

        ┌───────────────┴───────────────┐

        │                               │

   Public Website                 CiviCRM

        │                               │

        └───────────────┬───────────────┘

                        │

                  MariaDB Database

                        │

                 Automated Backups

                        │

               Off-site Backup Storage
```

---

# Primary Components

## WordPress

Responsibilities:

* public website
* blog/news
* content management
* page editing
* themes
* SEO
* user authentication

WordPress should remain the primary content management system.

---

## CiviCRM

Responsibilities:

* contacts
* organizations
* households
* volunteers
* donors
* events
* memberships
* email
* activities
* reports
* custom fields
* tags
* relationships

CiviCRM is the organizational database.

---

## Custom Plugin

All CoCoDems-specific functionality should live inside a custom plugin.

Examples include:

* custom reports
* Action Network integration
* VAN synchronization
* volunteer workflows
* committee management
* media contact tools

The custom plugin should contain nearly all project-specific business logic.

---

## Theme

The visual presentation of the website should remain independent of CRM functionality.

Business logic should never live inside the theme.

---

# Data Ownership

The CRM is the canonical database for organizational information.

Examples:

* volunteers
* donors
* media
* elected officials
* committee members
* newsletter subscribers
* organizations

External systems should synchronize with the CRM whenever practical.

---

# External Systems

The prototype is expected to coexist with several existing systems.

## NGP VAN

Purpose:

* voter file
* canvassing
* voter contact history

The CRM should complement—not replace—VAN.

Future work may include synchronization.

---

## Action Network

Purpose:

* advocacy
* petitions
* email campaigns

Possible future integration through APIs.

---

## Mobilize

Purpose:

* volunteer recruitment
* event registration

Future synchronization may be desirable.

---

# Deployment Architecture

Three environments are maintained.

## Local

Purpose:

* local development environment
* quick development at testing before committing to Github

Characteristics:

* fake email delivery
* non-production data
* Docker Compose brings up WordPress, CiviCRM, MariaDB, and Nginx with one command

---

## Staging

Purpose:

* testing
* experimentation
* demonstrations
* pull request validation

Characteristics:

* single EC2 instance (no load balancer)
* TLS via Certbot on the instance
* **access control** via WordPress and CiviCRM roles and permissions; optional HTTP basic auth (`scripts/setup-staging-auth.sh`) is available but not used by default, to keep committee review simple
* **data** — sample or empty data during early demos; later, a sanitized copy of production may be loaded for feature testing (see [roadmap.md](roadmap.md) Phase 1 P2 sync milestone)
* **fake email delivery** — outbound mail must not reach real inboxes, even if contact records contain real addresses (configure CiviCRM/WordPress mail accordingly)
* **no production API keys** — do not configure staging with credentials for external services (Action Network, payment processors, production SMTP, etc.) that could affect live systems; use sandbox or test keys, or leave integrations disabled until deliberately configured
* safe for development

See [deployment.md](deployment.md) for the staging deploy runbook.

---

## Production

Purpose:

Serve the live Columbia County Democrats CRM and website.

Characteristics:

* single EC2 instance (no load balancer)
* TLS via Certbot on the instance
* real users
* real email
* production backups
* monitored
* secure

---

# Infrastructure

Infrastructure should be reproducible.

Long-term goals include:

* Infrastructure as Code
* Terraform
* Docker
* GitHub Actions

A new environment should be creatable from an empty AWS account with minimal manual steps.

---

# Repository Strategy

Track:

* custom plugins
* custom themes
* Terraform
* Docker
* documentation
* deployment scripts

Do not track:

* WordPress core
* CiviCRM core
* uploads
* database dumps
* secrets

---

# Security Principles

The system contains sensitive political information.

Security requirements include:

* least privilege
* MFA for administrators
* encrypted HTTPS
* automated security updates
* regular backups
* audit logging
* strong password policy

No API keys or credentials should ever be committed to Git.

---

# Future Multi-County Architecture

The prototype targets one county.

Future expansion should support multiple counties.

Likely deployment model:

```
County A
    │
WordPress
    │
CiviCRM

County B
    │
WordPress
    │
CiviCRM

County C
    │
WordPress
    │
CiviCRM
```

Each county should have:

* independent database
* independent website
* independent administrators
* independent backups

Shared code should come from Git rather than a shared database.

This approach minimizes operational complexity while allowing a common software platform.

---

# Success Criteria

The prototype will be considered successful if it demonstrates:

* replacement of multiple spreadsheets with structured CRM data
* integration with a WordPress website
* manageable deployment workflow
* automated backups
* reproducible infrastructure
* maintainable custom code
* clear documentation
* a foundation that other county Democratic organizations could adopt

---

# Long-Term Vision

The ultimate objective is not merely to build software.

It is to create an organizational platform that preserves institutional knowledge, reduces volunteer workload, improves collaboration, and strengthens local Democratic organizations.

Technology should serve organizing—not the other way around.
