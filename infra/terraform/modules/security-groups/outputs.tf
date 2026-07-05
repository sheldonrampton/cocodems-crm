output "web_security_group_id" {
  description = "Security group ID for web traffic."
  value       = aws_security_group.web.id
}

output "ssh_security_group_id" {
  description = "Security group ID for SSH, or null if SSH is disabled."
  value       = length(aws_security_group.ssh) > 0 ? aws_security_group.ssh[0].id : null
}

output "instance_security_group_ids" {
  description = "Security group IDs to attach to the application EC2 instance."
  value = compact([
    aws_security_group.web.id,
    length(aws_security_group.ssh) > 0 ? aws_security_group.ssh[0].id : null,
  ])
}
