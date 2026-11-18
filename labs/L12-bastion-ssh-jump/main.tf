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
      lab        = "L12-bastion-ssh-jump"
      project    = "aws-lab-terraform"
      managed_by = "terraform"
    }
  }
}

module "bastion_pair" {
  source = "../../modules/bastion-pair"

  name_prefix       = "saa-l12"
  aws_region        = var.aws_region
  public_key        = var.public_key
  admin_cidr        = var.admin_cidr
  enable_eic_prefix = false
  create_iam_role   = false
}

output "bastion_public_ip" {
  description = "SSH entry point: ssh -J ec2-user@<this IP> ec2-user@<private IP>."
  value       = module.bastion_pair.bastion_public_ip
}

output "private_instance_id" {
  description = "Private host instance ID."
  value       = module.bastion_pair.private_instance_id
}

output "private_instance_private_ip" {
  description = "Private IPv4 address of saa-l12-ec2-private."
  value       = module.bastion_pair.private_instance_private_ip
}

output "key_pair_name" {
  description = "Lab key pair name."
  value       = module.bastion_pair.key_pair_name
}
