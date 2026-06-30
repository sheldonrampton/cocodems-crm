# ADR-0003: Use Terraform for Infrastructure as Code

**Status:** Accepted

**Date:** 2026-06-29

# Context

The CoCoDems CRM requires at least two cloud environments — staging and production — to host WordPress, CiviCRM, and MariaDB. See [architecture.md](../architecture.md).

The project is maintained primarily by volunteers. Infrastructure must be:

* reproducible from source control
* documented well enough for a new volunteer to understand and modify
* safe to change in staging before applying to production
* extensible so other county Democratic parties can deploy independent instances from the same codebase

Manual server setup (clicking through a cloud provider console, copying configuration between environments) does not meet these requirements. Configuration drift, undocumented changes, and difficult disaster recovery are likely without infrastructure as code.

Docker Compose in `docker/` addresses **local development** only. Cloud hosting for staging and production needs a separate, version-controlled approach.

# Decision

Use **Terraform** to define and manage cloud infrastructure for staging and production environments.

Infrastructure code will live in `infra/terraform/` with:

* reusable **modules** for shared resources (compute, database, networking, backups)
* thin **environment** directories (`environments/staging`, `environments/production`) that compose modules with environment-specific variables

Terraform is the single source of truth for cloud resources. Manual console changes should be avoided; any emergency manual fix should be backported into Terraform.

# Rationale

## Advantages

* **Reproducibility.** A new environment can be created from an empty AWS account with minimal manual steps, as required by [architecture.md](../architecture.md).
* **Version control.** Infrastructure changes are reviewed in pull requests alongside application code, with a clear history of who changed what and why.
* **Environment parity.** Staging and production share the same modules, reducing "works in staging, breaks in production" surprises caused by divergent manual setups.
* **Multi-county readiness.** Parameterized modules support deploying independent county instances (separate database, website, and administrators) from shared Git code.
* **Volunteer handoff.** Declarative `.tf` files and plan/apply workflows are easier to audit than a collection of undocumented console settings.
* **AI-assisted maintenance.** Terraform's declarative, text-based configuration aligns with the project's goal of AI-friendly development and documentation.
* **Ecosystem maturity.** Terraform has broad AWS provider support, extensive documentation, and is widely understood by contributors.

## Alternatives considered

| Alternative | Why not chosen |
|-------------|----------------|
| Manual AWS console setup | No version history, high drift risk, poor reproducibility for additional counties |
| AWS CloudFormation | Viable, but HCL is generally more readable; smaller volunteer pool likely to know CloudFormation |
| Pulumi / CDK | Adds a general-purpose programming layer that increases complexity for a volunteer team |
| Ansible / shell scripts only | Good for configuration management, but weaker for declarative resource lifecycle and state tracking |
| Platform-as-a-service (managed WordPress) | Less control over CiviCRM, backups, and customization; higher recurring cost at scale |

## Disadvantages

* **Learning curve.** Volunteers must understand Terraform concepts (state, modules, providers, plan/apply).
* **State management.** Remote state (e.g., S3 with locking) must be configured and protected; state files contain sensitive metadata.
* **Provider coupling.** Infrastructure is expressed against the AWS provider; migrating cloud vendors would require rewriting modules.
* **Apply discipline.** Production changes require careful review; `terraform apply` can destroy resources if misconfigured.

# Consequences

* Cloud infrastructure is defined in `infra/terraform/` and tracked in Git per [architecture.md](../architecture.md).
* Secrets (API keys, database passwords) are **not** stored in `.tf` files; they use AWS SSM Parameter Store, Secrets Manager, or CI/CD secrets.
* Remote state with locking is required for staging and production; local state is acceptable only for ephemeral experiments.
* GitHub Actions workflows will run `terraform fmt`, `terraform validate`, and `terraform plan` on pull requests that touch `infra/`.
* Production applies should be gated (manual approval or restricted workflow) with a documented rollback procedure in deployment documentation.
* Docker Compose remains the tool for local development; Terraform does not replace it.
* Coding conventions for Terraform are documented in [coding-standards.md](../coding-standards.md).
