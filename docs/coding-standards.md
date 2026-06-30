# Coding Standards

**Version:** 0.1 (Draft)

These conventions apply to all code in the CoCoDems CRM repository. They reflect the guiding principles in [architecture.md](architecture.md): prefer configuration over custom code, keep custom code isolated, and optimize for volunteer maintainability and AI-assisted development.

When a standard conflicts with an upstream framework convention (WordPress, CiviCRM, Terraform), follow the upstream convention unless there is a documented reason not to (record exceptions in [decision-log.md](decision-log.md)).

---

# General Principles

1. **Minimal custom code.** Use CiviCRM and WordPress features before writing new code.
2. **No core modifications.** Never edit WordPress core, CiviCRM core, or third-party plugins. Extend via hooks, APIs, and custom plugins.
3.  **Business logic in the plugin.** The `cocodems-custom` plugin holds project-specific logic. Themes handle presentation only.
4. **Readable over clever.** Future volunteers and AI assistants must be able to understand the code without oral history.
5. **Document non-obvious decisions.** If the "why" is not clear from the code, add a comment or ADR entry.

---

# PHP

PHP code lives primarily in `wordpress/wp-content/plugins/cocodems-custom/` and optionally in `mu-plugins/`.

## Version and style

* Target **PHP 8.1+** (match the Docker/production runtime).
* Follow **[WordPress PHP Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/php/)** for WordPress-facing code.
* Follow **[PSR-12](https://www.php-fig.org/psr/psr-12/)** for namespaced classes inside the custom plugin.
* Use strict types where practical: `declare(strict_types=1);` at the top of new class files.

## Naming

| Element | Convention | Example |
|---------|------------|---------|
| Plugin namespace | `CoCoDems\Crm\` | `CoCoDems\Crm\Volunteer\SignupHandler` |
| Functions (global WP hooks) | `cocodems_` prefix, snake_case | `cocodems_register_post_types()` |
| Classes | PascalCase | `CommitteeRepository` |
| Methods | camelCase | `getActiveMembers()` |
| Constants | UPPER_SNAKE_CASE | `COCODEMS_CRM_VERSION` |

## WordPress integration

* Register hooks in a central bootstrap file or dedicated loader class; avoid scattered `add_action` calls without documentation.
* Prefix all custom post types, taxonomies, options keys, and transients with `cocodems_`.
* Use WordPress APIs for HTTP, scheduling (`wp_schedule_event`), and database access (`$wpdb` or `$wpdb->prepare` — never interpolate user input into SQL).
* Enqueue scripts and styles only on pages that need them.

## CiviCRM integration

* Use the **CiviCRM API v4** (`Civi\Api4\`) for new code; avoid deprecated API v3 unless required by an existing extension.
* Do not modify CiviCRM database tables directly — use the API so hooks and audit logic fire correctly.
* Wrap CiviCRM calls in thin service classes inside the plugin (e.g., `ContactService`, `EventService`) to keep WordPress hooks readable.
* Export CiviCRM configuration (custom fields, relationship types, tags) via CiviCRM's export tools or API-backed migration scripts stored in `scripts/`.

## Error handling

* Log errors with `error_log()` or WordPress's logging in development; use structured messages that include context (contact ID, operation name).
* Fail gracefully in user-facing flows — show a clear message, do not expose stack traces.
* Never commit `var_dump`, `print_r`, or temporary debug exits.

## File organization

```text
cocodems-custom/
├── cocodems-custom.php          # Plugin header, bootstrap
├── includes/
│   ├── class-plugin.php         # Main plugin class
│   ├── Admin/
│   ├── CiviCRM/
│   ├── Integrations/
│   └── REST/
├── assets/
│   ├── js/
│   └── css/
└── templates/                   # PHP templates for shortcodes/blocks
```

---

# JavaScript

Frontend JavaScript for the custom plugin and theme.

## Version and style

* Target **ES2020+**; transpile only if browser support requires it.
* Use **WordPress `@wordpress/scripts`** or the project's bundler config when building blocks or admin UI.
* Follow **[WordPress JavaScript Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/javascript/)**.
* Prefer `@wordpress/element` and `@wordpress/components` for admin React UI consistent with the block editor.

## Naming and structure

| Element | Convention | Example |
|---------|------------|---------|
| Source files | kebab-case | `volunteer-signup-form.js` |
| Exported functions | camelCase | `handleFormSubmit` |
| WordPress script handles | `cocodems-` prefix | `cocodems-volunteer-form` |
| CSS classes (JS-generated) | BEM with `cocodems-` prefix | `cocodems-form__field` |

## Practices

* Pass configuration from PHP via `wp_localize_script()` or `wp_add_inline_script()` — do not hardcode API URLs or nonces in standalone JS files.
* Use `fetch` with WordPress REST API nonces for authenticated requests.
* No jQuery in new code unless required for compatibility with CiviCRM or WordPress admin components that depend on it.
* Keep bundles small; load admin scripts only on relevant admin screens.

---

# Terraform

Infrastructure code lives in `infra/terraform/`.

## Layout

* **Modules** (`modules/`) — reusable, parameterized resources (VPC, EC2, RDS, S3, etc.).
* **Environments** (`environments/staging`, `environments/production`) — thin wrappers that call modules with environment-specific variables.
* No secrets in `.tf` files — use AWS SSM Parameter Store, Secrets Manager, or Terraform Cloud variables marked sensitive.

## Naming

| Element | Convention | Example |
|---------|------------|---------|
| Resources | `{project}_{env}_{resource}` | `cocodems_staging_db` |
| Variables | snake_case | `instance_type` |
| Modules | kebab-case directory names | `modules/mariadb/` |
| Tags | `Project`, `Environment`, `ManagedBy` | `ManagedBy = terraform` |

## Practices

* Pin provider versions in `versions.tf`.
* Run `terraform fmt` before committing; CI should enforce formatting.
* Run `terraform validate` and plan in CI for every pull request touching `infra/`.
* Document required manual steps (DNS delegation, initial secrets) in `infra/terraform/README.md`.
* Prefer remote state (S3 + DynamoDB lock) for staging and production; local state only for ephemeral experiments.
* Use `lifecycle` blocks and `prevent_destroy` on production databases and backup buckets.

---

# Docker

Local development configuration lives in `docker/`.

## Practices

* Pin image versions in `docker-compose.yml` (e.g., `mariadb:10.11`, not `mariadb:latest`).
* Mount WordPress and plugin source from the host for live editing; do not bake development code into production images.
* Store environment-specific values in `.env` (gitignored); document every variable in `.env.example`.
* Use named volumes for database persistence across container restarts.
* Production images (if added later) should be multi-stage, non-root where possible, and defined separately from the dev Compose file.
* Never commit database dumps, uploads, or TLS private keys.

## Service naming

Use consistent service names in Compose: `nginx`, `wordpress`, `mariadb`, `php`.

---

# Git

## Branching

| Branch | Purpose |
|--------|---------|
| `main` | Stable, deployable code |
| `feature/<short-description>` | New features |
| `fix/<short-description>` | Bug fixes |
| `infra/<short-description>` | Terraform and deployment changes |

Open pull requests for all changes to `main`. Require at least one review for production-impacting work when team size allows.

## Commits

Write commit messages in **imperative mood**, present tense, ~50-character subject line, optional body explaining *why*.

```text
Add volunteer signup REST endpoint

Expose POST /wp-json/cocodems/v1/volunteers for form submissions.
Uses CiviCRM API v4 to create contacts with Volunteer tag.
```

Prefixes (optional but encouraged):

| Prefix | Use |
|--------|-----|
| `Add` | New feature or file |
| `Fix` | Bug fix |
| `Update` | Enhancement to existing behavior |
| `Refactor` | Code change without behavior change |
| `Docs` | Documentation only |
| `Infra` | Terraform, Docker, CI |
| `Test` | Tests only |

Do not commit secrets, `.env` files, database dumps, or vendor directories unless explicitly vendored by project policy.

## Pull requests

* Link related issues when applicable.
* Describe what changed and how to test it.
* Include screenshots for UI changes.
* Ensure CI passes before merge.

---

# Documentation

Documentation lives in `docs/` and inline where code is non-obvious.

## Markdown files

* Use sentence case for headings (`## Contact types`, not `## Contact Types`).
* Keep [vision.md](vision.md) and [architecture.md](architecture.md) as the source of truth for *why*; this file covers *how* to write code.
* Record significant decisions in [decision-log.md](decision-log.md) using ADR format (context, decision, consequences).
* Update [data-model.md](data-model.md) when adding custom fields, relationship types, or new entity mappings.
* Update [roadmap.md](roadmap.md) when milestones are completed or reprioritized.

## Code comments

* Explain *why*, not *what*, unless the logic is genuinely complex.
* Use PHPDoc blocks on public classes and methods; include `@param` and `@return` types.
* TODO comments must include context: `// TODO(cocodems#42): Add Mobilize sync after API credentials are provisioned.`

## README files

Each major directory (`infra/terraform/`, `docker/`, `wordpress/`, plugin root) should have a README with setup steps, not merely a file listing.

---

# Testing

* Place automated tests in `tests/`.
* PHPUnit for plugin PHP logic; use WordPress test suite or Brain Monkey for unit tests that mock WordPress.
* Run tests in CI on every pull request.
* Name test methods descriptively: `test_duplicate_email_rejected_on_volunteer_signup()`.
* Test CiviCRM integration against a fixture database or mocked API responses — do not require production data in tests.

Add tests when fixing bugs (regression test) or implementing non-trivial business logic. Do not add tests that merely assert framework behavior.

---

# Security

* Validate and sanitize all user input using WordPress functions (`sanitize_text_field`, `wp_kses_post`, etc.).
* Check capabilities and nonces on every admin action and REST endpoint.
* Store API keys in environment variables or AWS Secrets Manager — never in Git, never in the database as plain text if avoidable.
* Depend on automated security updates for WordPress, CiviCRM, and base Docker images.
* Review third-party dependencies before adding them; prefer WordPress and CiviCRM built-ins.

---

# Tooling

Run these before opening a pull request when applicable:

| Tool | Scope | Command |
|------|-------|---------|
| PHPCS (WordPress rules) | PHP | `phpcs --standard=WordPress path/to/plugin` |
| PHPStan or Psalm | PHP (optional, recommended) | project-specific |
| ESLint | JavaScript | via `@wordpress/scripts lint-js` |
| Prettier | JS, JSON, Markdown | project config |
| `terraform fmt` | Terraform | `terraform fmt -recursive infra/` |
| `terraform validate` | Terraform | per environment |

CI (`.github/workflows/ci.yml`) should automate these checks as the project matures.

---

# AI-Assisted Development

This project expects AI tools to read and modify the codebase. To support that:

* Keep files focused and under ~400 lines where practical.
* Use descriptive file and function names over abbreviations.
* Reference related docs in module README files (`See docs/data-model.md for entity mappings`).
* When an AI or human makes a non-obvious choice, add an ADR rather than a long comment in code.

These standards evolve. Propose changes via pull request with updates to this document and, if needed, an ADR explaining the rationale.
