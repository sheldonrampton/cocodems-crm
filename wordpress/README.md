# WordPress

This directory holds **custom** WordPress code tracked in Git. WordPress core, CiviCRM core, and uploads are installed by Docker and are not committed.

## Custom code

| Path | Purpose |
|------|---------|
| `wp-content/plugins/cocodems-custom/` | CoCoDems business logic and integrations |
| `wp-content/themes/cocodems-theme/` | Public theme (optional during CRM-only adoption) |

## Local development

Start the stack from the repository root:

```bash
cp .env.example .env   # edit passwords first
docker compose --project-directory . -f docker/docker-compose.yml up --build
```

The custom plugin and theme directories are bind-mounted into the running container. Changes on the host appear immediately after a page refresh.

See [docker/README.md](../docker/README.md) for full setup instructions.
