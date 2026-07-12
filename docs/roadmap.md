# Roadmap

**Version:** 0.4 (Draft)

This document outlines prioritized milestones from the initial prototype through a production-ready platform. Milestones are ordered by dependency and value — later items assume earlier ones are substantially complete.

The roadmap follows the balanced approach described in [vision.md](vision.md): build the CRM in parallel with existing Democratic Party tools (NGP VAN, Action Network, Mobilize) rather than attempting a disruptive all-at-once migration.

Staging is deployed early (Phase 1) so the Communications Committee can review a working demo before being asked to provide spreadsheets and other records for import in later phases.

---

# Phase 0 — Foundation

**Goal:** Establish a reproducible development environment and shared documentation.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P0 | Repository structure | Directories, `.gitignore`, and README match the planned layout |
| P0 | Core documentation | `vision.md`, `architecture.md`, `roadmap.md`, `data-model.md`, and `coding-standards.md` published |
| P0 | Local development environment | Docker Compose brings up WordPress, CiviCRM, MariaDB, and Nginx with one command |
| P1 | Environment configuration | `.env.example` documents all required variables; secrets never committed |
| P1 | Decision log | ADR template and first entries for major technology choices |

---

# Phase 1 — Staging Environment

**Goal:** Deploy a staging site for testing, demonstrations, and pull-request validation — including demos for the CoCoDems Communications Committee before real data is imported.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P0 | Terraform baseline | Staging environment defined in `infra/terraform/environments/staging` |
| P0 | Staging deployment | WordPress + CiviCRM running on staging; automated deploy from `main` or a staging branch |
| P0 | Staging access | Committee members can log in via WordPress and browse CiviCRM; HTTP basic auth is optional and not used by default (see [deployment.md](deployment.md)) |
| P0 | Staging data policy | Safe for experimentation: fake email delivery (no mail to real inboxes); no production API keys for external integrations; sample or empty data until import phases; staging may hold full or sanitized production copies when sync scripts exist (Phase 6) |
| P1 | CI pipeline | GitHub Actions run linting and basic tests on every pull request — see `.github/workflows/ci.yml` |
| P1 | Database backup/restore | `backup-db.sh`, `restore-db.sh`, and scheduled S3 backups — see [deployment.md](deployment.md#database-backup-and-restore) |

Phase 1 staging infrastructure is **complete** when the above milestones are met. Cross-environment database sync is deferred until production exists ([Phase 6](#phase-6--production-launch)).

---

# Phase 2 — Preliminary Data Import

**Goal:** Configure CiviCRM for Columbia County and load representative sample data on staging to validate the data model — before requesting spreadsheets and other records from committee members.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P0 | Contact types configured | Individual, Organization, and Household contact types enabled per [data-model.md](data-model.md) |
| P0 | Custom fields and tags | Fields for volunteer interests, committee roles, media beats, and elected-office metadata |
| P1 | Sample data | Representative test contacts, households, organizations, and events loaded (not committee source data) |
| P1 | Basic reports | At least three CiviCRM reports replace common spreadsheet views (volunteer list, donor list, media contacts) |
| P1 | Custom plugin scaffold | `cocodems-custom` plugin registered with autoloading and a health-check admin page |
| P2 | Theme integration | Child theme displays public pages; no CRM business logic in the theme |

---

# Phase 3 — Data Consolidation

**Goal:** Import real committee and organizational records — replacing disconnected spreadsheets with structured CRM data while keeping external systems authoritative where appropriate.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P0 | Data inventory | Spreadsheet and external-system audit documented (sources, owners, update frequency) |
| P0 | Import pipeline | CSV import scripts or CiviCRM import profiles for each major list |
| P0 | Deduplication rules | Matching strategy for name, email, phone, and address documented and tested |
| P1 | Volunteer records | Volunteer spreadsheet migrated; interests and availability captured as custom fields or tags |
| P1 | Donor records | Donor list migrated with contribution history where available |
| P1 | Media and elected-official contacts | Separate contact subtypes or tags applied; relationships to organizations recorded |
| P2 | Newsletter subscribers | Subscriber list imported; email consent and opt-out status preserved |
| P2 | Household grouping | Related individuals linked via CiviCRM households and relationships |

---

# Phase 4 — Custom Workflows

**Goal:** Implement CoCoDems-specific business logic in the custom plugin using CiviCRM APIs rather than core modifications.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P0 | Committee management | Groups or custom entities represent committees; membership tracked via relationships |
| P1 | Volunteer workflows | Sign-up forms, interest matching, and activity logging for volunteer shifts |
| P1 | Event enhancements | Event registration integrated with CiviCRM participants; optional Mobilize sync design |
| P2 | Custom reports | Plugin-provided reports not achievable with stock CiviCRM report builder |
| P2 | Admin dashboards | Summary views for committee chairs (member counts, upcoming events, open tasks) |
| P3 | Media contact tools | Quick lookup and activity logging for press outreach |

---

# Phase 5 — External Integrations

**Goal:** Synchronize with Democratic Party organizing infrastructure; CRM remains the canonical source for organizational contacts.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P1 | Action Network — design | API mapping documented; sync direction and conflict resolution defined |
| P1 | Action Network — MVP | One-way or bidirectional sync for contacts and/or event sign-ups |
| P2 | NGP VAN — design | Scope limited to complement (not replace) voter file; export/import boundaries documented |
| P2 | NGP VAN — MVP | Volunteer or activist list export to VAN, or survey result import from VAN |
| P3 | Mobilize — design | Event and volunteer registration sync strategy documented |
| P3 | Mailchimp migration | If applicable, subscriber history migrated and Mailchimp retired |

Integration work should follow the principle in [architecture.md](architecture.md): external systems synchronize *with* the CRM; the CRM does not attempt to replace specialized tools like VAN.

---

# Phase 6 — Production Launch

**Goal:** Serve the live Columbia County Democrats website and CRM with real users, real email, and operational safeguards.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P0 | Production Terraform | Production environment defined with stricter security groups, backups, and monitoring |
| P0 | HTTPS and DNS | TLS certificates provisioned; domain points to production |
| P0 | MFA and access control | Administrator MFA enforced; least-privilege WordPress and CiviCRM roles |
| P0 | Automated backups | Daily database and file backups to off-site storage; restore tested |
| P1 | Security hardening | Security updates automated; audit logging enabled; strong password policy |
| P1 | Production deployment | Manual or gated deploy workflow with rollback procedure |
| P1 | Operator runbook | `deployment.md` covers deploy, rollback, backup restore, and incident response |
| P1 | Cross-environment data sync | Operator scripts (after production is live): `sync-staging-to-production.sh` (promote reviewed staging changes); `sync-production-to-staging.sh` (full production copy to staging); `sync-production-to-staging-sanitized.sh` (sanitized copy for demos/training). Staging is not required to stay sanitized — use the script that matches the workflow. |
| P2 | Incremental adoption | At least one committee actively using CRM instead of spreadsheets |
| P2 | Email delivery | CiviCRM mailings or integrated provider sending production email |

---

# Phase 7 — Platform Readiness

**Goal:** Prepare the codebase and documentation for adoption by other county Democratic parties.

| Priority | Milestone | Success criteria |
|----------|-----------|------------------|
| P1 | Configuration over code | County-specific settings externalized (names, domains, custom field labels) |
| P1 | Multi-environment Terraform module | Reusable modules parameterized for a new county deployment |
| P2 | Onboarding documentation | Step-by-step guide for standing up a new county instance |
| P2 | License and governance | Open-source license chosen; contribution guidelines published |
| P3 | Second county pilot | Another Wisconsin county party deploys from shared Git code with independent database |

Each county deployment should remain independent — separate database, website, administrators, and backups — as described in [architecture.md](architecture.md).

---

# Milestone Dependencies

```
Phase 0 (Foundation)
    │
    ▼
Phase 1 (Staging Environment)
    │
    ▼
Phase 2 (Preliminary Data Import)
    │
    ▼
Phase 3 (Data Consolidation)
    │
    ▼
Phase 4 (Custom Workflows)
    │
    ├──► Phase 5 (Integrations)
    │         │
    └─────────┼──► Phase 6 (Production)
              │         │
              │         ▼
              └──► Phase 7 (Platform Readiness)
```

Phase 2 validates the CRM configuration and data model on staging using sample data. Phase 3 imports real committee records once the Communications Committee has seen a demo and agreed to provide source files. Integration work (Phase 5) should not block production launch for core CRM features, but should be planned before retiring external list-management tools.

---

# Out of Scope (for Now)

The following items are intentionally deferred:

* Replacing NGP VAN as the voter file system
* Real-time bidirectional sync with all external platforms
* Shared multi-tenant database across counties
* Mobile-native applications
* Advanced fundraising compliance (FEC reporting, etc.)

Revisit these when Phase 6 success criteria are met and volunteer capacity allows.
