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

# Private S3 bucket with a sample image asset for verifying S3 Gateway
# endpoint access (`aws s3 ls` and `aws s3 cp`) from the private instance.
resource "aws_s3_bucket" "lab_assets" {
  bucket_prefix = "saa-l11-assets-"
  force_destroy = true

  tags = {
    Name = "saa-l11-assets"
  }
}

resource "aws_s3_bucket_public_access_block" "lab_assets" {
  bucket = aws_s3_bucket.lab_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "sample_image" {
  bucket       = aws_s3_bucket.lab_assets.id
  key          = "sample.svg"
  source       = "${path.module}/assets/sample.svg"
  etag         = filemd5("${path.module}/assets/sample.svg")
  content_type = "image/svg+xml"
}

output "s3_bucket_name" {
  description = "Private S3 bucket name for testing the S3 Gateway endpoint."
  value       = aws_s3_bucket.lab_assets.bucket
}

output "s3_sample_object_uri" {
  description = "S3 URI of the sample image asset."
  value       = "s3://${aws_s3_bucket.lab_assets.bucket}/${aws_s3_object.sample_image.key}"
}

# S3 Gateway VPC endpoint attached to the private route table so the private
# instance can reach S3 without a NAT gateway or public internet route.
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = module.bastion_pair.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.bastion_pair.private_route_table_id]

  tags = {
    Name = "saa-l11-vpce-s3"
  }
}

output "s3_vpc_endpoint_id" {
  description = "S3 Gateway VPC endpoint ID."
  value       = aws_vpc_endpoint.s3_gateway.id
}

# DynamoDB Gateway VPC endpoint on the private route table, same pattern as S3.
resource "aws_vpc_endpoint" "dynamodb_gateway" {
  vpc_id            = module.bastion_pair.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.bastion_pair.private_route_table_id]

  tags = {
    Name = "saa-l11-vpce-dynamodb"
  }
}

# Small on-demand table with one item so the private host has something to
# read through the DynamoDB endpoint (`aws dynamodb scan`).
resource "aws_dynamodb_table" "lab_items" {
  name         = "saa-l11-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "saa-l11-items"
  }
}

resource "aws_dynamodb_table_item" "sample" {
  table_name = aws_dynamodb_table.lab_items.name
  hash_key   = aws_dynamodb_table.lab_items.hash_key

  item = jsonencode({
    id      = { S = "hello from hangyao with dynamoDB" }
    message = { S = "read through the DynamoDB Gateway endpoint" }
  })
}

# CloudWatch Logs Interface endpoint (PrivateLink) in the private subnet.
# Private DNS makes logs.<region>.amazonaws.com resolve to the endpoint ENI.
resource "aws_security_group" "vpce_logs" {
  name        = "saa-l11-sg-vpce"
  description = "CloudWatch Logs Interface endpoint: HTTPS from the private host SG."
  vpc_id      = module.bastion_pair.vpc_id

  tags = {
    Name = "saa-l11-sg-vpce"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_logs_https" {
  security_group_id            = aws_security_group.vpce_logs.id
  description                  = "HTTPS from the private host"
  referenced_security_group_id = module.bastion_pair.sg_private_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "logs_interface" {
  vpc_id              = module.bastion_pair.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [module.bastion_pair.private_subnet_id]
  security_group_ids  = [aws_security_group.vpce_logs.id]
  private_dns_enabled = true

  tags = {
    Name = "saa-l11-vpce-cw"
  }
}

resource "aws_cloudwatch_log_group" "lab" {
  name              = "/saa-l11/lab"
  retention_in_days = 1

  tags = {
    Name = "saa-l11-log-group"
  }
}

resource "aws_cloudwatch_log_stream" "lab" {
  name           = "sample"
  log_group_name = aws_cloudwatch_log_group.lab.name
}

output "dynamodb_vpc_endpoint_id" {
  description = "DynamoDB Gateway VPC endpoint ID."
  value       = aws_vpc_endpoint.dynamodb_gateway.id
}

output "dynamodb_table_name" {
  description = "DynamoDB table for testing the Gateway endpoint."
  value       = aws_dynamodb_table.lab_items.name
}

output "logs_vpc_endpoint_id" {
  description = "CloudWatch Logs Interface VPC endpoint ID."
  value       = aws_vpc_endpoint.logs_interface.id
}

output "log_group_name" {
  description = "Log group for testing the CloudWatch Logs Interface endpoint."
  value       = aws_cloudwatch_log_group.lab.name
}
