output "site_domain" {
  description = "Configured site domain. Create an A record at your DNS provider pointing to public_ip."
  value       = var.site_domain
}

output "public_ip" {
  description = "Elastic IP for DNS A record. See docs/dns.md."
  value       = module.app.public_ip
}

output "public_dns" {
  description = "AWS public DNS name for the staging instance."
  value       = module.app.public_dns
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = module.app.instance_id
}

output "backup_bucket_name" {
  description = "S3 bucket for database and file backups."
  value       = module.backups.bucket_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "availability_zone" {
  description = "Availability zone of the staging instance."
  value       = module.app.availability_zone
}

output "dns_instructions" {
  description = "Next step after terraform apply."
  value       = "Create an A record: ${var.site_domain} -> ${module.app.public_ip} (TTL 300). Then configure TLS. See docs/dns.md."
}
