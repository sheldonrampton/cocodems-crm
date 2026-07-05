variable "name_prefix" {
  description = "Prefix for EC2 resource names."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance."
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs to attach to the instance."
  type        = list(string)
}

variable "instance_profile_name" {
  description = "IAM instance profile name."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 30
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH. Prefer SSM Session Manager when possible."
  type        = string
  default     = null
}

variable "site_domain" {
  description = "Public hostname for this instance (used in tags; DNS is configured externally)."
  type        = string
}

variable "user_data" {
  description = "Optional cloud-init user data script."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name

  user_data = var.user_data != "" ? var.user_data : null

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-app"
    SiteDomain  = var.site_domain
    Application = "cocodems-crm"
  })
}

resource "aws_eip" "app" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eip"
  })
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
