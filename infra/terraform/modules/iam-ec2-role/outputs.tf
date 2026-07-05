output "role_arn" {
  description = "IAM role ARN attached to the EC2 instance."
  value       = aws_iam_role.app.arn
}

output "instance_profile_name" {
  description = "IAM instance profile name for the EC2 instance."
  value       = aws_iam_instance_profile.app.name
}
