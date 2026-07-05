variable "name_prefix" {
  description = "Prefix for security group names."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to attach security groups to."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to connect on port 22. Use an empty list to disable SSH."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}

resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web"
  description = "HTTP and HTTPS for WordPress and CiviCRM"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-web-sg"
  })
}

resource "aws_security_group" "ssh" {
  count = length(var.ssh_allowed_cidrs) > 0 ? 1 : 0

  name        = "${var.name_prefix}-ssh"
  description = "SSH access for administration"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ssh-sg"
  })
}
