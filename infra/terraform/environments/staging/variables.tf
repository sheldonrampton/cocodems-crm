variable "aws_region" {
  description = "AWS region for staging resources."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name used in resource naming."
  type        = string
  default     = "cocodems"
}

variable "county_slug" {
  description = "Short county identifier (e.g. columbia)."
  type        = string
  default     = "columbia"
}

variable "site_domain" {
  description = "Public hostname for staging (DNS configured externally). See docs/dns.md."
  type        = string
}

variable "backup_bucket_name" {
  description = "Globally unique S3 bucket name for staging backups."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the staging app server."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 30
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH access. Use an empty list to disable SSH (use SSM instead)."
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "Optional EC2 key pair name. Leave null to use SSM Session Manager only."
  type        = string
  default     = null
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR block."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the public subnet. Leave empty for the first AZ in the region."
  type        = string
  default     = ""
}
