terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      lab        = "L11-vpc-endpoints"
      project    = "aws-lab-terraform"
      managed_by = "terraform"
    }
  }
}

# Base only, by design: no NAT gateway, no default route in the private route
# table, no endpoints. Stage 1 of the lab watches `aws s3 ls` time out before
# you create the S3 Gateway endpoint by hand; Stage 2 adds the NAT gateway,
# the private default route, and the CloudWatch Logs Interface endpoint.
module "bastion_pair" {
  source = "../../modules/bastion-pair"

  name_prefix       = "saa-l11"
  aws_region        = var.aws_region
  public_key        = var.public_key
  admin_cidr        = var.admin_cidr
  enable_eic_prefix = true
  create_iam_role   = true
}

output "vpc_id" {
  description = "Lab VPC. Attach the Stage 1 Gateway endpoint here."
  value       = module.bastion_pair.vpc_id
}

output "public_subnet_id" {
  description = "Public subnet for the Stage 2 NAT gateway."
  value       = module.bastion_pair.public_subnet_id
}

output "private_subnet_id" {
  description = "Private subnet for the Stage 2 Interface endpoint."
  value       = module.bastion_pair.private_subnet_id
}

output "private_route_table_id" {
  description = "Private route table. Stage 2 adds the NAT default route here."
  value       = module.bastion_pair.private_route_table_id
}

output "sg_private_id" {
  description = "Private host security group. Stage 2 allows 443 from it to the endpoint SG."
  value       = module.bastion_pair.sg_private_id
}

output "bastion_public_ip" {
  description = "Bastion public IP, the SSH entry point."
  value       = module.bastion_pair.bastion_public_ip
}

output "private_instance_id" {
  description = "Private host instance ID."
  value       = module.bastion_pair.private_instance_id
}

output "private_instance_private_ip" {
  description = "Private IPv4 address of saa-l11-ec2-private."
  value       = module.bastion_pair.private_instance_private_ip
}
