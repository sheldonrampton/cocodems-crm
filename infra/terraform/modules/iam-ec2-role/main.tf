variable "name_prefix" {
  description = "Prefix for IAM resource names."
  type        = string
}

variable "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket the instance may read and write."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-role"
  })
}

data "aws_iam_policy_document" "backup_access" {
  statement {
    sid = "BackupBucketAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]

    resources = [
      var.backup_bucket_arn,
      "${var.backup_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "backup_access" {
  name   = "${var.name_prefix}-backup-access"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.backup_access.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.app.name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ec2-profile"
  })
}
