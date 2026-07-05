locals {
  name_prefix = "${var.project_name}-staging-${var.county_slug}"

  common_tags = {
    Project     = var.project_name
    Environment = "staging"
    County      = var.county_slug
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix         = local.name_prefix
  cidr_block          = var.vpc_cidr_block
  public_subnet_cidr  = var.public_subnet_cidr
  availability_zone   = var.availability_zone
  tags                = local.common_tags
}

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  ssh_allowed_cidrs = var.ssh_allowed_cidrs
  tags              = local.common_tags
}

module "backups" {
  source = "../../modules/s3-backups"

  bucket_name = var.backup_bucket_name
  tags        = local.common_tags
}

module "iam" {
  source = "../../modules/iam-ec2-role"

  name_prefix       = local.name_prefix
  backup_bucket_arn = module.backups.bucket_arn
  tags              = local.common_tags
}

module "app" {
  source = "../../modules/ec2-app"

  name_prefix           = local.name_prefix
  subnet_id             = module.vpc.public_subnet_id
  security_group_ids    = module.security_groups.instance_security_group_ids
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  root_volume_size_gb   = var.root_volume_size_gb
  key_name              = var.key_name
  site_domain           = var.site_domain
  tags                  = local.common_tags
}
