# Remote state backend — configure after bootstrapping the state bucket.
#
# 1. Create the S3 bucket and DynamoDB lock table (see infra/terraform/README.md).
# 2. Copy backend.tf.example to backend.tf and fill in your bucket name.
# 3. Run: terraform init -migrate-state
#
# Until then, Terraform uses local state in this directory (gitignored).
