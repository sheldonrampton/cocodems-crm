variable "bucket_name" {
  description = "Globally unique S3 bucket name for backups."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}

variable "daily_backup_retention_days" {
  description = "Days to retain daily database backups under cocodems/db/daily/."
  type        = number
  default     = 30
}

variable "monthly_backup_retention_days" {
  description = "Days to retain monthly database backups under cocodems/db/monthly/ (1st-of-month snapshots)."
  type        = number
  default     = 365
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-daily-db-backups"
    status = "Enabled"

    filter {
      prefix = "cocodems/db/daily/"
    }

    expiration {
      days = var.daily_backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  rule {
    id     = "expire-monthly-db-backups"
    status = "Enabled"

    filter {
      prefix = "cocodems/db/monthly/"
    }

    expiration {
      days = var.monthly_backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  # Pre-tiered backups (cocodems/db/cocodems-*.sql.gz) — expire after daily retention.
  rule {
    id     = "expire-legacy-db-backups"
    status = "Enabled"

    filter {
      prefix = "cocodems/db/cocodems"
    }

    expiration {
      days = var.daily_backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}
