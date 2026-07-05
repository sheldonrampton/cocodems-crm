# Deployment

Procedures for deploying CoCoDems CRM to staging and production.

Staging infrastructure (EC2, VPC, S3) is created with Terraform. The **application** (Docker, WordPress, CiviCRM) is deployed separately using the scripts in `scripts/`.

See also:

* [infra/terraform/environments/staging/README.md](../infra/terraform/environments/staging/README.md)
* [dns.md](dns.md)

---

# Staging deployment overview

Staging and production each run on a **single EC2 instance** with an Elastic IP. There is no Application Load Balancer — DNS points directly at the instance, and TLS terminates on host Nginx (Certbot / Let's Encrypt).

```
Internet → DNS A record → EC2 Elastic IP
                              │
                    Host Nginx (:80 / :443, Certbot TLS)
                              │
                    Docker Nginx (127.0.0.1:8080)
                              │
                    PHP + WordPress + CiviCRM
                              │
                         MariaDB
```

Staging and production are **separate** EC2 instances (separate Terraform environments), each following this same pattern.

| Component | Where it runs |
|-----------|---------------|
| Terraform | Your laptop — creates EC2, EIP, S3, security groups per environment |
| `.env` on server | `/opt/cocodems-crm/.env` — environment-specific URL and secrets |
| `.env` in repo root | Local Docker only — keep `http://localhost:8080` |

---

# Staging — first-time deploy

## 1. Prerequisites

* `terraform apply` completed for staging
* DNS A record: `site_domain` → `terraform output public_ip` (see [dns.md](dns.md))
* AWS CLI configured locally (for SSM access)
* Git repository URL (or copy the repo to the server another way)

## 2. Bootstrap the server

Connect via SSM (replace instance ID from `terraform output instance_id`):

```bash
aws ssm start-session --target INSTANCE_ID
```

On the instance, become root and bootstrap:

```bash
sudo -i
git clone https://github.com/sheldonrampton/cocodems-crm.git /opt/cocodems-crm
cd /opt/cocodems-crm
bash scripts/bootstrap-staging-server.sh
```

`bootstrap-staging-server.sh` installs Docker, Nginx, and Certbot, and removes the default Nginx site (which otherwise causes empty replies on port 80).

## 3. Configure staging environment

Still on the server:

```bash
cd /opt/cocodems-crm
cp .env.staging.example .env
nano .env
```

Set at minimum:

| Variable | Example |
|----------|---------|
| `SITE_DOMAIN` | `crm-staging.governation.org` |
| `CIVICRM_UF_BASEURL` | `http://crm-staging.governation.org` until TLS is set up; then `https://…` |
| `MYSQL_ROOT_PASSWORD` | strong random password |
| `MYSQL_PASSWORD` | strong random password |
| `CIVICRM_ADMIN_PASS` | admin login password |

## 4. Deploy the application

```bash
sudo -u ubuntu bash scripts/deploy-staging.sh
```

First run builds Docker images and installs WordPress + CiviCRM (several minutes).

Verify the site responds (HTTP or HTTPS depending on your TLS setup):

```bash
curl -I "https://crm-staging.governation.org/"
```

Open in browser: `https://crm-staging.governation.org/wp-login.php`

## 5. Enable HTTPS (Certbot on EC2)

TLS terminates on the EC2 instance using **Let's Encrypt** via Certbot. ACM certificates require a load balancer and are **not** used in this architecture.

After HTTP works:

```bash
sudo bash scripts/setup-staging-tls.sh
```

This runs Certbot on host Nginx, updates WordPress URLs to `https://`, and updates `.env`.

If you previously created an ACM certificate for this domain, it can remain in AWS for other uses, but it cannot be attached to Nginx on EC2. Use Certbot for HTTPS on the instance.

## 6. Password-protect staging (optional)

HTTP basic auth is **optional**. WordPress and CiviCRM roles already control what logged-in users can see and do.

Consider basic auth only if you want the **entire** staging site (including public pages and `/wp-login.php`) hidden from anonymous visitors. Skip this step if you prefer to rely on WordPress/CiviCRM accounts and strong passwords for committee members.

```bash
sudo bash scripts/setup-staging-auth.sh
```

---

# Staging — updates

Pull latest code and rebuild on the server:

```bash
cd /opt/cocodems-crm
git pull
sudo -u ubuntu bash scripts/deploy-staging.sh
```

---

# Troubleshooting

**Empty reply / connection closed on port 80**

Default Nginx site or a partial install is listening. Run `sudo bash scripts/bootstrap-staging-server.sh` again, then redeploy.

**HTTPS fails but HTTP works**

Run `sudo bash scripts/setup-staging-tls.sh` after DNS points at the instance. Port 80 must be reachable from the internet for Certbot validation.

**Wrong redirects (localhost, HTTP instead of HTTPS)**

`CIVICRM_UF_BASEURL` on the **server** `.env` must match the public `https://` URL. Re-run `setup-staging-tls.sh` or update WordPress `home` and `siteurl` manually.

**`ERR_TOO_MANY_REDIRECTS` on `/wp-login.php` or `/wp-admin`**

WordPress is behind two proxies (host Nginx → Docker Nginx → PHP) and does not detect HTTPS. It redirects to `https://…/wp-login.php` while thinking the request is HTTP, causing an infinite loop. Pull the latest code and restart Docker Nginx:

```bash
cd /opt/cocodems-crm
git pull
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.staging.yml restart nginx
```

If it persists, add the proxy HTTPS block to `/var/www/private/wp-config.php` inside the PHP container (or re-run `sudo bash scripts/setup-staging-tls.sh`).

**CiviCRM shows only “CiviCRM Home” / no menus or contact search**

CiviCRM CSS and JavaScript did not load — usually because the site was installed over HTTP and TLS was enabled later, or because **resource URL** settings are wrong. WordPress URLs may be correct while CiviCRM still points at bad paths (common: `imageUploadURL` missing `/persist/contribute/`). On the server:

```bash
cd /opt/cocodems-crm
git pull
# Ensure .env has CIVICRM_UF_BASEURL=https://your-domain
bash scripts/fix-civicrm-urls.sh
bash scripts/diagnose-civicrm-urls.sh   # verify runtime URLs
```

`imageUploadURL` should end with `/wp-content/uploads/civicrm/persist/contribute/`. Then hard-refresh CiviCRM (Cmd+Shift+R) and visit the menu rebuild URL if needed:

```
https://your-domain/wp-admin/admin.php?page=CiviCRM&q=civicrm/menu/rebuild&reset=1
```

**Cannot connect via SSM**

Instance needs the IAM profile from Terraform and SSM agent (pre-installed on Ubuntu AMIs). Check security groups allow outbound HTTPS. Staging is in **us-east-2** — pass `--region us-east-2` if your CLI default region differs.

**`address already in use` on `127.0.0.1:8080`**

Docker Compose **merges** `ports` from both compose files. If `docker-compose.yml` and `docker-compose.staging.yml` each publish port 8080, the second bind fails even when no other process is using the port. The fix is to keep host port publishing only in `docker-compose.staging.yml` (and `docker-compose.local.yml` for local dev).

After pulling the latest code:

```bash
cd /opt/cocodems-crm
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.staging.yml down
sudo -u ubuntu bash scripts/deploy-staging.sh
```

Verify the merged config shows a **single** port mapping:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.staging.yml config | grep -A2 'nginx:' | grep ports -A2
# Expected: only "127.0.0.1:8080:80"
```

---

# Production

Production uses the same single-EC2 pattern (no load balancer). `environments/production` Terraform and production deploy scripts are planned for Phase 6. TLS on production will also use Certbot on the instance unless the architecture changes.
