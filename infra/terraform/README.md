# Terraform

Infrastructure as code for CoCoDems CRM staging and production environments on AWS. See [ADR-0003](../../docs/adr/0003-use-terraform.md) and [ADR-0004](../../docs/adr/0004-aws-ec2.md).

DNS is **not** managed here — domain owners configure records manually. See [docs/dns.md](../../docs/dns.md) and [ADR-0006](../../docs/adr/0006-external-dns.md).

## Layout

```text
infra/terraform/
├── modules/
│   ├── vpc/              # VPC, public subnet, internet gateway
│   ├── security-groups/  # HTTP/HTTPS and optional SSH
│   ├── s3-backups/       # Encrypted backup bucket
│   ├── iam-ec2-role/     # EC2 role (SSM + S3 backups)
│   └── ec2-app/          # Ubuntu app server + Elastic IP
└── environments/
    └── staging/          # Columbia County staging stack
```

Production (`environments/production`) will reuse the same modules with stricter settings.

## Prerequisites

* [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
* AWS CLI configured with credentials for the target account
* An AWS account with permission to create VPC, EC2, S3, and IAM resources

### Install Terraform (macOS)

Homebrew core no longer ships `terraform`. Use the HashiCorp tap:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

Alternatively, download a binary from [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install).

## Quick start (staging)

```bash
cd infra/terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: site_domain, backup_bucket_name, ssh_allowed_cidrs

terraform init
terraform plan
terraform apply
```

After `apply`, note the `public_ip` output and create a DNS A record per [docs/dns.md](../../docs/dns.md).

## Remote state (recommended before team use)

By default, staging uses **local state** until you configure a remote backend.

1. Create an S3 bucket and DynamoDB table for state locking (one-time per AWS account):

```bash
# Example — replace BUCKET and TABLE with unique names
aws s3api create-bucket --bucket cocodems-terraform-state-UNIQUE --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2
aws s3api put-bucket-versioning --bucket cocodems-terraform-state-UNIQUE \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name cocodems-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-2
```

2. Copy `backend.tf.example` to `backend.tf` and fill in bucket and table names.
3. Run `terraform init -migrate-state`.

## Variables

Staging variables are documented in [environments/staging/terraform.tfvars.example](environments/staging/terraform.tfvars.example). Required:

| Variable | Description |
|----------|-------------|
| `site_domain` | Public hostname (DNS configured externally) |
| `backup_bucket_name` | Globally unique S3 bucket name |

Secrets (database passwords, API keys) are **not** stored in Terraform. They belong in SSM Parameter Store or on-instance `.env` files managed by deployment scripts.

## What Terraform creates (staging)

| Resource | Purpose |
|----------|---------|
| VPC + public subnet | Network for the app server |
| Security groups | HTTP/HTTPS (and optional SSH) |
| EC2 instance (Ubuntu 22.04) | Runs Docker / WordPress / CiviCRM (configured by deploy scripts) |
| Elastic IP | Stable address for external DNS |
| S3 backup bucket | Off-site database backups (`daily/` 30d, `monthly/` 365d lifecycle) |
| IAM instance profile | SSM Session Manager + S3 backup access |

Terraform does **not** install WordPress or CiviCRM — that is a separate deployment step (Phase 1 milestone).

## Common commands

```bash
terraform fmt -recursive ../../
terraform validate
terraform plan
terraform output public_ip
terraform output dns_instructions
```

Connect to the instance without SSH keys:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

## Conventions

See [docs/coding-standards.md](../../docs/coding-standards.md#terraform) for naming, tagging, and workflow conventions.
