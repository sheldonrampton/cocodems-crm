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
* [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) installed (`brew install --cask session-manager-plugin` on macOS)
* Git repository URL (or copy the repo to the server another way)

Staging Terraform uses **us-east-2**. Pass `--region us-east-2` on AWS CLI commands if your default region differs.

## 2. Bootstrap the server

Connect via SSM (replace instance ID from `terraform output instance_id`):

```bash
aws ssm start-session --target INSTANCE_ID --region us-east-2
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

Verify the site responds over **HTTP** (HTTPS comes in step 5):

```bash
curl -I "http://crm-staging.governation.org/"
```

After step 5 (TLS), use `https://`. Re-running `deploy-staging.sh` restores HTTPS automatically if a Let's Encrypt certificate already exists.

Open in browser: `http://crm-staging.governation.org/wp-login.php`

## 5. Enable HTTPS (Certbot on EC2)

TLS terminates on the EC2 instance using **Let's Encrypt** via Certbot. ACM certificates require a load balancer and are **not** used in this architecture.

After HTTP works:

```bash
sudo bash scripts/setup-staging-tls.sh
```

This runs Certbot on host Nginx, updates WordPress and CiviCRM URLs to `https://`, and updates `.env` (including `scripts/fix-civicrm-urls.sh`).

If you previously created an ACM certificate for this domain, it can remain in AWS for other uses, but it cannot be attached to Nginx on EC2. Use Certbot for HTTPS on the instance.

## 6. Password-protect staging (optional)

HTTP basic auth is **optional**. WordPress and CiviCRM roles already control what logged-in users can see and do.

Consider basic auth only if you want the **entire** staging site (including public pages and `/wp-login.php`) hidden from anonymous visitors. Skip this step if you prefer to rely on WordPress/CiviCRM accounts and strong passwords for committee members.

```bash
sudo bash scripts/setup-staging-auth.sh
```

## 7. Staging mail policy (no real email)

Phase 1 staging must not send mail to real inboxes ([roadmap](roadmap.md), [architecture](architecture.md)). CiviCRM has two separate mail concerns:

| Setting | Purpose | Staging recommendation |
|---------|---------|------------------------|
| **Environment** | Global production vs staging mode | Set to **Staging** |
| **Outbound Email** | SMTP / sending mailings | **Disable Outbound Email** (auto when Environment = Staging via UI) |
| **Default mailbox** | Inbound IMAP for bounces / email-to-activity | **Skip for now** unless you are testing CiviMail |
| **Scheduled jobs** | Cron sends mailings, fetches bounces | **Disable** mail-related jobs |

### Recommended UI steps (do this once)

1. **Administer → System Settings → Debugging and Error Handling**
   - Set **Environment** to **Staging**
   - Save

   When set via the UI, CiviCRM automatically sets outbound mail to [Disable Outbound Email](https://docs.civicrm.org/sysadmin/en/latest/misc/staging-production/).

2. **Administer → System Settings → Outbound Email**
   - Confirm **Disable Outbound Email** is selected (not SMTP or `mail()`).

3. **Administer → System Settings → Scheduled Jobs**
   - Set **Enabled?** to **No** for:
     - Send Scheduled Mailings
     - Fetch Bounces
     - Process Inbound Emails
   - Do not configure CiviCRM cron on staging until you deliberately test mail.

4. **Default mailbox (System Status warning)**
   - The “configure a default mailbox” check is for **inbound bounce processing** ([CiviMail mail accounts](https://docs.civicrm.org/sysadmin/en/latest/setup/civimail/)).
   - For committee demos and CRM testing **without CiviMail**, it is fine to **leave this warning** until you need outbound mail in a later phase.
   - Do **not** point staging at production IMAP/SMTP credentials.
   - When you later test mailings on staging, use either:
     - **Redirect to Database** (Administer → System Settings → Outbound Email) so messages are stored in CiviCRM but not sent, or
     - A dedicated throwaway staging mailbox plus disabled bounce-fetch jobs until you are ready.

### Optional: harden via `civicrm.settings.php`

To survive database copies from production or manual UI changes, add overrides in `/var/www/html/wp-content/uploads/civicrm/civicrm.settings.php` (inside the PHP container):

```php
// cocodems-crm staging mail policy
$civicrm_setting['domain']['environment'] = 'Staging';
$civicrm_setting['Mailing Preferences']['mailing_backend']['outBound_option'] = 0; // Disable outbound email

// Discard any mail that does slip through (belt-and-suspenders)
define('CIVICRM_MAIL_LOG', '/dev/null');
```

`outBound_option` values: `0` = disabled, `5` = redirect to database (useful when testing template content without sending).

After editing, run `bash scripts/fix-civicrm-urls.sh` or `cv flush` inside the PHP container.

### Testing mail content later (still no real delivery)

If you want committee members to **preview** mailing HTML without delivery:

1. Set Environment to **Staging** (keep outbound disabled or use **Redirect to Database**).
2. Create test mailings; they appear in CiviCRM rather than being delivered ([redirect to database](https://civicrm.stackexchange.com/questions/21986/email-redirect-to-database-setting-for-civicrm-settings-php)).

Production mail (real SMTP, bounce mailbox, cron) is a **Phase 6** milestone ([roadmap](roadmap.md)).

**CiviCRM System Status: “Private Files Readable” / debug log downloadable**

Nginx does not use `.htaccess`, so CiviCRM upload directories must be blocked in `docker/nginx/default.conf`. Pull latest code and reload Docker Nginx:

```bash
docker compose --project-directory . -f docker/docker-compose.yml -f docker/docker-compose.staging.yml restart nginx
```

Verify a blocked path returns 404, e.g. `https://your-domain/wp-content/uploads/civicrm/ConfigAndLog/` (should not list or download files). Re-check System Status in CiviCRM.

---

# Staging — updates

Pull latest code and rebuild on the server:

```bash
cd /opt/cocodems-crm
git pull
sudo -u ubuntu bash scripts/deploy-staging.sh
```

## CiviCRM version upgrades

The CiviCRM version is set in `docker/php/Dockerfile` (default **6.16.0**). Rebuilding the PHP image does not replace the plugin in the existing Docker volume — run the upgrade script after deploy:

```bash
cd /opt/cocodems-crm
git pull
sudo -u ubuntu bash scripts/deploy-staging.sh
sudo -u ubuntu bash scripts/upgrade-civicrm.sh
```

Verify in the CiviCRM UI footer or with `cv ev 'echo CRM_Utils_System::version();'` inside the PHP container. See [CiviCRM 6.16 release notes](https://civicrm.org/blog/dev-team/civicrm-616-release).

If `cv upgrade:db` fails with `Permission denied` on `/var/www/.cv/upgrade`, pull the latest `upgrade-civicrm.sh` (uses `XDG_STATE_HOME`) or rebuild the PHP image.

**Docker Compose warns `The "g6" variable is not set`**

A password in `.env` contains `$` followed by letters (e.g. `pass$word`). Compose treats that as a variable reference. Escape each `$` as `$$` in password values, then redeploy.

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

`imageUploadURL` should end with `/wp-content/uploads/civicrm/persist/contribute/`. Leave **Custom CSS URL** blank (our fix script clears it). Then hard-refresh CiviCRM (Cmd+Shift+R) and visit the menu rebuild URL if needed:

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

**`ERR_CONNECTION_CLOSED` on HTTPS after `deploy-staging.sh`**

`deploy-staging.sh` reinstalls an HTTP-only host Nginx config. That removes Certbot's `:443` server block until HTTPS is restored. Fix:

```bash
sudo bash scripts/setup-staging-tls.sh
```

Or pull the latest `deploy-staging.sh`, which re-runs Certbot automatically when a certificate already exists. Verify port 443 is listening: `sudo ss -tlnp | grep 443`

**CiviCRM WordPress Access Control checkboxes do not toggle**

The permission matrix can look fine but checkboxes ignore clicks. Common causes:

1. **Browser extension** (e.g. LastPass) — try an incognito window with extensions disabled.
2. **Another WordPress plugin** injecting admin CSS — on staging, try deactivating plugins not in this repo (e.g. `import-users-from-csv`) one at a time.
3. **CSS overlay** — pull latest code (`cocodems-custom` includes admin CSS fixes) and hard-refresh.
4. **Saving after toggling** — the matrix posts many fields; PHP `max_input_vars` must be ≥ 2000 (set in `docker/php/Dockerfile`). Rebuild the PHP image after pulling: `sudo -u ubuntu bash scripts/deploy-staging.sh`

Inspect a checkbox in DevTools: if the `checked` attribute changes on click but the box looks empty, it is a visual/CSS issue. If `checked` never changes, an overlay or extension is blocking the click.

---

# Production

Production uses the same single-EC2 pattern (no load balancer). `environments/production` Terraform and production deploy scripts are planned for Phase 6. TLS on production will also use Certbot on the instance unless the architecture changes.
