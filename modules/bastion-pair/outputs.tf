output "vpc_id" {
  description = "Lab VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "Public subnet holding the bastion."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet. L11 learners attach Stage 2 endpoints here."
  value       = aws_subnet.private.id
}

output "private_route_table_id" {
  description = "Private route table. Ships with local routes only; L11 learners add the Stage 2 default route."
  value       = aws_route_table.private.id
}

output "sg_bastion_id" {
  description = "Bastion security group."
  value       = aws_security_group.bastion.id
}

output "sg_private_id" {
  description = "Private host security group."
  value       = aws_security_group.private.id
}

output "bastion_public_ip" {
  description = "Public IP of the bastion."
  value       = aws_instance.bastion.public_ip
}

output "private_instance_id" {
  description = "Instance ID of the private host."
  value       = aws_instance.private.id
}

output "private_instance_private_ip" {
  description = "Private IPv4 address of the private host."
  value       = aws_instance.private.private_ip
}

output "key_pair_name" {
  description = "Name of the lab key pair."
  value       = aws_key_pair.this.key_name
}
