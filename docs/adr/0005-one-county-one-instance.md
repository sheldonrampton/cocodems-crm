# ADR-0005: One County, One Instance

**Status:** Accepted

**Date:** 2026-06-29

# Context

The long-term goal is a reusable CRM platform that multiple Wisconsin county Democratic parties could adopt. See [architecture.md](../architecture.md) and [ADR-0001](0001-project-vision.md).

A key architectural question is how to host multiple counties:

* **One shared installation** — WordPress Multisite and/or CiviCRM Multisite, with many county sites or organizations on a single database and application stack
* **One installation per county** — a separate WordPress + CiviCRM instance (and database) for each county party

WordPress Multisite allows a network of sites under one WordPress installation. CiviCRM also supports multi-domain and multi-tenant configurations. These approaches can reduce per-county hosting cost and centralize administration.

However, county parties are independent organizations with their own volunteers, data, security boundaries, and operational schedules. A failure or compromise in one county's environment should not affect others.

Separately, not every county will want to replace its public website on day one. Columbia County Democrats currently host their site on Squarespace. The CRM prototype may need to deliver CiviCRM value — contact management, volunteers, events, donations — without requiring an immediate website migration.

# Decision

Deploy **one WordPress + CiviCRM instance per county**, each with its **own database**, **own administrators**, and **own backups**.

Do **not** use WordPress Multisite or CiviCRM Multisite to host multiple counties on a shared installation.

Shared code (custom plugins, themes, Terraform modules) comes from Git and is deployed to each county's instance independently.

Counties may adopt the platform incrementally:

* **CRM only** — run CiviCRM (with WordPress as the required host) while keeping an existing public website such as Squarespace
* **Full stack** — migrate the public website to WordPress when the county is ready

For CoCoDems, the initial deployment will likely be **CRM only**, retaining Squarespace for the public site. WordPress remains installed because CiviCRM requires it, but the county is not obligated to migrate web content immediately.

# Rationale

## Advantages

* **Independent backups.** Each county's database and files can be backed up and restored on its own schedule without affecting other counties.
* **Safer upgrades.** WordPress, CiviCRM, and plugin updates can be tested and applied per county. A failed upgrade in one county does not take down the statewide platform.
* **Security isolation.** A compromised admin account, plugin vulnerability, or misconfiguration is contained within one county's instance.
* **Volunteer administration.** Each county controls its own user accounts and permissions. County volunteers do not need access to a shared network admin console or other counties' data.
* **Disaster recovery.** Restoring one county after data loss or infrastructure failure is a bounded operation — restore one database and one file set — rather than untangling a shared multi-tenant system.
* **Operational simplicity.** Per-county instances match how county parties actually organize: independent entities sharing software, not sharing a database.
* **Flexible website adoption.** A county can use CiviCRM for CRM workflows while keeping Squarespace (or another platform) for its public site. WordPress + CiviCRM integration preserves the option to migrate the website later without re-platforming the CRM.

## Alternatives considered

| Alternative | Why not chosen |
|-------------|----------------|
| **WordPress Multisite** | Centralizes many sites under one WordPress install. A core or plugin failure affects all counties. Network admin privileges are broader than most county volunteers need. Backup and restore of a single county's data is harder to isolate. |
| **CiviCRM Multisite** | Shares one CiviCRM database across domains or organizations. Cross-county data leakage risk increases. Upgrade and migration complexity rises. Does not align with independent county data ownership. |
| **Shared SaaS tenant** | Single application serving all counties with row-level tenancy. Requires custom multi-tenant engineering not justified for the prototype; conflicts with volunteer-operated, independently administered county parties. |

## Disadvantages

* **Higher baseline cost.** Each county pays for its own compute and database resources rather than sharing one server.
* **More deployments.** Terraform and deployment scripts must be run (or automated) per county, though modules make this repeatable.
* **Code drift risk.** Counties on different upgrade schedules may run different plugin versions unless updates are managed deliberately.
* **WordPress overhead for CRM-only counties.** CiviCRM requires WordPress even when the county does not use WordPress for its public website, adding a component that must be maintained and secured.

## CRM-only deployment

WordPress and CiviCRM are coupled — CiviCRM runs as a WordPress plugin and cannot be deployed standalone in this architecture. That coupling is intentional:

* It enables a future Squarespace → WordPress migration when CoCoDems chooses
* It does not require that migration at initial CRM deployment
* The public Squarespace site can link to CiviCRM forms, event pages, or admin URLs on the CRM subdomain while editorial content remains on Squarespace

# Consequences

* [architecture.md](../architecture.md) multi-county diagram reflects one WordPress + CiviCRM stack per county, not a shared multisite network.
* Terraform modules in `infra/terraform/` are parameterized for a **single county deployment**; standing up a new county means applying the same module with county-specific variables (domain, credentials, tags).
* Each county gets independent S3 backup buckets (or prefixes), RDS instances (or separate databases), and IAM boundaries as defined in [ADR-0004](0004-aws-ec2.md).
* Custom plugins and themes are versioned in Git and deployed to each instance — shared code, separate runtime.
* CoCoDems staging and production should support a **CRM subdomain** (e.g., `crm.example.org`) distinct from the Squarespace public site until a website migration is planned.
* Documentation must cover the CRM-only adoption path: minimum WordPress configuration, CiviCRM admin access, and optional public CiviCRM pages without a full theme rollout.
* Multi-county cost estimates and onboarding guides should assume N independent instances, not one shared multisite host.
