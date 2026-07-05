output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Elastic IP address — create an A record at your DNS provider pointing here."
  value       = aws_eip.app.public_ip
}

output "public_dns" {
  description = "AWS public DNS name for the instance."
  value       = aws_eip.app.public_dns
}

output "availability_zone" {
  description = "Availability zone of the EC2 instance."
  value       = aws_instance.app.availability_zone
}

output "ami_id" {
  description = "AMI ID used for the instance."
  value       = aws_instance.app.ami
}
