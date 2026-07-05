output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "Public subnet ID for the application server."
  value       = aws_subnet.public.id
}

output "availability_zone" {
  description = "Availability zone used by the public subnet."
  value       = local.az
}
