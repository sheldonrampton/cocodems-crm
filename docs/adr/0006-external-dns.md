# ADR-0006: Do Not Manage DNS with Terraform or AWS

**Status:** Accepted

**Date:** 2026-07-03

# Context

[ADR-0003](0003-use-terraform.md) chose Terraform for infrastructure as code, and [ADR-0004](0004-aws-ec2.md) chose AWS EC2 for compute. AWS Route 53 is the natural companion for DNS, and Terraform has full Route 53 support.

However, domain ownership in this project is distributed:

* The **Columbia County Democrats** already own a domain managed through GoDaddy.
* The project's primary maintainer (Sheldon Rampton) owns several additional domains that may be used for staging or development.
* If this platform is adopted by **other county Democratic parties**, each county may already own a domain through whatever registrar or DNS provider they chose independently.

Requiring all participants to move their DNS to Route 53 — or granting Terraform access to their registrar accounts — adds friction, cost, and trust barriers that are disproportionate to the benefit.

DNS configuration for a WordPress + CiviCRM site is straightforward: typically one or two A/CNAME records pointing at the EC2 instance's public IP or load balancer. This is well within the ability of a volunteer to set up manually in any DNS provider's console.

# Decision

**Do not use Terraform or AWS Route 53 to provision or manage DNS** for staging or production instances.

Instead:

* The domain name is specified as an **environment variable** (`CIVICRM_UF_BASEURL` and related settings) in `.env` or the deployment configuration.
* Domain owners create DNS records manually at their chosen provider (GoDaddy, Cloudflare, Namecheap, etc.) pointing to the EC2 instance or load balancer.
* Deployment documentation will include the required DNS records but will not automate their creation.

# Rationale

## Advantages

* **Flexibility.** Each county keeps its existing registrar and DNS provider. No vendor lock-in beyond what the county already chose.
* **No credential sharing.** Terraform does not need API access to anyone's registrar account, reducing the security surface.
* **Lower cost.** Route 53 hosted zones have a small monthly fee per domain. Existing DNS providers are typically already paid for.
* **Simpler onboarding.** A new county deployment only needs to add one or two DNS records — a task most volunteers can complete in minutes with documentation guidance.
* **Decoupled lifecycle.** DNS changes (e.g., adding a subdomain for email) happen independently of Terraform runs, avoiding accidental infrastructure drift in unrelated resources.

## Alternatives considered

| Alternative | Why not chosen |
|-------------|----------------|
| **AWS Route 53 managed by Terraform** | Clean automation, but requires every domain owner to delegate DNS to Route 53 or grant API credentials. Adds cost and registrar migration friction for each county. |
| **Terraform with multi-provider DNS** | Terraform has providers for Cloudflare, GoDaddy (community), etc., but supporting multiple DNS providers in shared modules adds complexity and maintenance burden with little benefit for a few static records. |
| **Automated DNS via deployment script** | Could use registrar APIs at deploy time, but same credential-sharing and multi-provider problems apply. |

## Disadvantages

* **Manual step.** DNS setup is not fully automated; a volunteer must create records by hand during initial deployment.
* **Documentation dependency.** The required DNS records must be clearly documented and kept up to date as the infrastructure evolves (e.g., if a load balancer replaces a static IP).
* **No automated validation.** Terraform cannot verify that DNS is correctly configured before proceeding with TLS certificate provisioning. Deployment scripts or runbooks should include a DNS check step.

# Consequences

* Terraform modules in `infra/terraform/` will **not** include `aws_route53_zone` or `aws_route53_record` resources.
* The domain/subdomain is passed into Terraform and application configuration as a variable, not created by it.
* `.env.example` and deployment documentation must clearly specify:
  * Which DNS records to create (A, CNAME, or both)
  * Where to point them (EC2 Elastic IP, ALB hostname, etc.)
  * Expected TTL values
* TLS certificate provisioning (e.g., AWS Certificate Manager with DNS validation) will require the domain owner to create a validation CNAME record manually, or use HTTP validation if supported.
* Future automation (e.g., a helper script that checks DNS propagation before deploying) is welcome but not required.
* [ADR-0004](0004-aws-ec2.md) references Route 53 for DNS management; that should be read as "Route 53 is available if desired" rather than "Route 53 is required."
