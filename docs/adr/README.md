# Architecture Decision Records

This directory contains **Architecture Decision Records (ADRs)** for the CoCoDems CRM project. Each ADR documents a significant technical or architectural choice: the context that led to it, the decision itself, the rationale (including alternatives considered), and the consequences for the codebase and operations.

ADRs exist so future volunteers — and AI-assisted development tools — can understand *why* the project is built the way it is, not merely *what* the current code does. See [architecture.md](../architecture.md) (principle 5: AI-friendly development) and [coding-standards.md](../coding-standards.md).

ADRs are **immutable once accepted**. If a decision is reversed or superseded, add a new ADR that references the old one and update the earlier record's status to `Superseded by ADR-NNNN`.

---

# Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-project-vision.md) | Project vision | Accepted | 2026-06-29 |
| [0002](0002-wordpress-civicrm.md) | Use WordPress + CiviCRM instead of Squarespace | Accepted | 2026-06-29 |
| [0003](0003-use-terraform.md) | Use Terraform for infrastructure as code | Accepted | 2026-06-29 |
| [0004](0004-aws-ec2.md) | Use AWS EC2 for cloud hosting | Accepted | 2026-06-29 |
| [0005](0005-one-county-one-instance.md) | One county, one instance | Accepted | 2026-06-29 |
| [0006](0006-external-dns.md) | Do not manage DNS with Terraform or AWS | Accepted | 2026-07-03 |

---

# ADR format

Use this structure for new records. Copy an existing ADR as a starting point.

```markdown
# ADR-NNNN: Short title

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-NNNN

**Date:** YYYY-MM-DD

# Context

What problem or question prompted this decision?

# Decision

What did we decide? State it clearly in one or two sentences.

# Rationale

## Advantages

* ...

## Alternatives considered

| Alternative | Why not chosen |
|-------------|----------------|
| ... | ... |

## Disadvantages

* ...

# Consequences

What follows from this decision? Include effects on code, infrastructure,
documentation, and ongoing maintenance.
```

Not every ADR needs every subsection, but **Context**, **Decision**, and **Consequences** are required.

---

# Adding a new ADR

1. Choose the next sequential number (`0006`, `0007`, …).
2. Create `docs/adr/NNNN-short-slug.md` using kebab-case for the slug.
3. Set initial status to `Proposed` while under review; change to `Accepted` when merged.
4. Add a row to the index table in this README.
5. Cross-reference related ADRs and docs (`architecture.md`, `roadmap.md`, etc.) where helpful.
6. Open a pull request so the team can review before the decision is treated as final.

---

# When to write an ADR

Write an ADR when a decision is:

* **Hard to reverse** — cloud provider, database engine, deployment model
* **Cross-cutting** — affects multiple parts of the stack or multiple counties
* **Non-obvious** — future readers would ask "why did we do it this way?"
* **Debatable** — reasonable alternatives existed and were considered

Skip an ADR for routine implementation choices that follow established conventions in [coding-standards.md](../coding-standards.md).

---

# Related documentation

* [vision.md](../vision.md) — project goals and strategy memo
* [architecture.md](../architecture.md) — system design and guiding principles
* [roadmap.md](../roadmap.md) — phased milestones
* [coding-standards.md](../coding-standards.md) — code and documentation conventions
