# Staging environment

Terraform configuration for the Columbia County Democrats **staging** CRM instance.

## Resources

This stack provisions a minimal single-server topology:

* VPC with one public subnet
* EC2 instance (Ubuntu 22.04, `t3.small` by default)
* Elastic IP for stable DNS
* S3 bucket for backups
* IAM role with SSM and S3 access

WordPress, CiviCRM, and Docker are deployed to the instance separately after infrastructure is created.

## Setup

```bash
cd infra/terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | What to set |
|----------|-------------|
| `site_domain` | Staging hostname, e.g. `crm-staging.yourdomain.org` |
| `backup_bucket_name` | Globally unique S3 name, e.g. `cocodems-staging-columbia-backups-abc123` |
| `ssh_allowed_cidrs` | Your IP as `/32`, or `[]` to use SSM only |
| `aws_region` | AWS region (default `us-east-2`) |

```bash
terraform init
terraform plan
terraform apply
```

## Local `.env` vs staging

The `.env` file in the **repository root** is only for **local Docker** (`docker compose`). Terraform does not read it and does not copy it to EC2.

| Setting | Local development | Staging server |
|---------|-------------------|----------------|
| File | `.env` at repo root | `.env` on the EC2 instance (created during app deploy) |
| `CIVICRM_UF_BASEURL` | `http://localhost:8080` | `https://crm-staging.governation.org` (your `site_domain`) |
| `HTTP_PORT` | `8080` | Usually `80` / `443` via Nginx on the host |

Changing the root `.env` after `terraform apply` does **not** update the staging server. Set `CIVICRM_UF_BASEURL` on the instance when you deploy WordPress/CiviCRM there.

## After apply

1. **DNS** — A record: `site_domain` → `public_ip`. See [docs/dns.md](../../../docs/dns.md).
2. **TLS** — Certbot on the EC2 instance (`scripts/setup-staging-tls.sh`). ACM is not used without a load balancer.
3. **Application** — [docs/deployment.md](../../../docs/deployment.md) (bootstrap + deploy scripts).
4. **Staging access (optional)** — `scripts/setup-staging-auth.sh` for HTTP basic auth, or rely on WordPress/CiviCRM roles.

## Outputs

```bash
terraform output public_ip
terraform output dns_instructions
terraform output backup_bucket_name
```

## Remote state

See [infra/terraform/README.md](../../README.md#remote-state-recommended-before-team-use) for S3 backend setup.
