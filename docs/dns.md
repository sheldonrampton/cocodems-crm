# DNS Configuration

This project does **not** automate DNS provisioning. Domain owners create DNS records manually at whatever registrar or DNS provider they already use (GoDaddy, Cloudflare, Namecheap, etc.). See [ADR-0006](adr/0006-external-dns.md) for the rationale.

This guide covers the records needed for staging and production deployments on AWS EC2.

---

## Prerequisites

Before configuring DNS you need:

1. **A domain or subdomain** you control (e.g. `crm.columbiademocrats.org`).
2. **The public IP or hostname** of your EC2 instance or load balancer. Terraform outputs this value after `terraform apply`. You can also find it in the AWS EC2 console under **Public IPv4 address** or **Public IPv4 DNS**.

---

## Required DNS records

### Single EC2 instance (typical for staging and early production)

| Record type | Host / name | Value | TTL |
|-------------|-------------|-------|-----|
| **A** | `crm.example.org` | EC2 Elastic IP (e.g. `54.123.45.67`) | 300 |

Use an **Elastic IP** rather than the instance's auto-assigned public IP. An Elastic IP persists across instance stop/start cycles so the DNS record does not need updating.

If your DNS provider does not support A records at the zone apex and you are using the bare domain (e.g. `example.org` rather than a subdomain), check whether your provider offers an **ALIAS** or **ANAME** pseudo-record. Otherwise use a subdomain.

### With an Application Load Balancer (future scaling)

| Record type | Host / name | Value | TTL |
|-------------|-------------|-------|-----|
| **CNAME** | `crm.example.org` | ALB DNS name (e.g. `cocodems-alb-123456.us-east-2.elb.amazonaws.com`) | 300 |

CNAME records cannot be placed at the zone apex (`example.org`). If you need the bare domain to point at an ALB, use a provider that supports ALIAS/ANAME records, or use a subdomain.

---

## CRM-only deployment (keeping Squarespace or another website)

If the county is using WordPress + CiviCRM only for CRM and keeping a separate public website (see [ADR-0005](adr/0005-one-county-one-instance.md)), point a **subdomain** at the CRM instance:

| Record type | Host / name | Value | TTL |
|-------------|-------------|-------|-----|
| **A** | `crm.example.org` | EC2 Elastic IP | 300 |

The main domain (`example.org`) continues to point at the existing website provider (Squarespace, Wix, etc.). No changes are needed to the main site's DNS.

Set `SITE_DOMAIN=crm.example.org` and `CIVICRM_UF_BASEURL=https://crm.example.org` in your deployment `.env`.

---

## TLS / HTTPS

HTTPS requires a TLS certificate. Two common approaches on AWS:

### AWS Certificate Manager (ACM) + Load Balancer

1. Request a certificate in ACM for your domain (e.g. `crm.example.org`).
2. ACM asks you to create a **CNAME validation record** at your DNS provider:

| Record type | Host / name | Value |
|-------------|-------------|-------|
| **CNAME** | `_abc123.crm.example.org` | `_def456.acm-validations.aws.` |

ACM provides the exact name and value. Create this record at your DNS provider and wait for validation (usually a few minutes, sometimes up to 30).

3. Attach the validated certificate to your ALB listener. Terraform handles this; the DNS validation record is the only manual step.

### Let's Encrypt (Certbot) on the EC2 instance

1. Point DNS at the instance (A record above).
2. Wait for propagation (check with `dig crm.example.org`).
3. Run Certbot on the instance:

```bash
sudo certbot --nginx -d crm.example.org
```

Certbot validates via HTTP (port 80 must be open) and installs the certificate automatically. Renewal is handled by a cron job or systemd timer.

No extra DNS records are needed for HTTP validation.

---

## Verifying DNS

After creating records, verify propagation before deploying:

```bash
# Check A record
dig +short crm.example.org A

# Check CNAME record (if using ALB)
dig +short crm.example.org CNAME

# Full lookup with TTL
dig crm.example.org
```

DNS propagation typically takes a few minutes but can take up to 48 hours depending on TTL settings and caching. Lower the TTL to 300 (5 minutes) before making changes, then raise it after confirming the records are correct.

---

## Environment variables

The domain is configured as an environment variable, not hardcoded in Terraform or application code.

| Variable | Where | Example |
|----------|-------|---------|
| `SITE_DOMAIN` | Terraform variables / `.env` | `crm.columbiademocrats.org` |
| `CIVICRM_UF_BASEURL` | Application `.env` | `https://crm.columbiademocrats.org` |

Terraform uses `SITE_DOMAIN` (or its equivalent `tfvar`) to configure security groups, TLS certificates, and Nginx server names. WordPress and CiviCRM use `CIVICRM_UF_BASEURL` for link generation and redirects.

These must match. If you change the domain after initial deployment, update both values and reconfigure TLS.

---

## Multi-county deployments

Each county gets its own domain or subdomain and its own EC2 instance (see [ADR-0005](adr/0005-one-county-one-instance.md)). The DNS instructions above apply independently to each county — each domain owner creates their own records at their own provider.

| County | Domain | DNS provider | Points to |
|--------|--------|--------------|-----------|
| Columbia | `crm.columbiademocrats.org` | GoDaddy | Columbia EC2 Elastic IP |
| Dane | `crm.danedems.org` | Cloudflare | Dane EC2 Elastic IP |
| Sauk | `crm.saukdems.org` | Namecheap | Sauk EC2 Elastic IP |

No coordination between DNS providers is required. Terraform modules are parameterized with `SITE_DOMAIN` per county.

---

## Common DNS providers — quick links

These are not endorsements; they are links to DNS management docs for providers county parties are likely to use.

* [GoDaddy — Manage DNS records](https://www.godaddy.com/help/manage-dns-records-680)
* [Cloudflare — Manage DNS records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/)
* [Namecheap — How to add DNS records](https://www.namecheap.com/support/knowledgebase/article.aspx/434/2237/how-do-i-set-up-host-records-for-a-domain/)
* [Google Domains — Manage resource records](https://support.google.com/domains/answer/3290350)
* [AWS Route 53 — Creating records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-creating.html) (if you choose to use Route 53 voluntarily)
