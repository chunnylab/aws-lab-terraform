variable "name_prefix" {
  description = "Prefix for every resource name, e.g. saa-l11 or saa-l12."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the lab VPC. Public and private /24s are carved from it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az" {
  description = "Availability Zone for both subnets."
  type        = string
  default     = "ap-southeast-1a"
}

variable "aws_region" {
  description = "Region, used to resolve the EC2 Instance Connect prefix list."
  type        = string
  default     = "ap-southeast-1"
}

variable "public_key" {
  description = "OpenSSH public key material for the lab key pair (aws_key_pair)."
  type        = string

  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) ", var.public_key))
    error_message = "public_key must be OpenSSH material starting with ssh-rsa or ssh-ed25519."
  }
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the bastion, usually your IP as /32."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid IPv4 CIDR, e.g. 203.0.113.5/32."
  }
}

variable "enable_eic_prefix" {
  description = "Also allow SSH from the EC2 Instance Connect prefix list (L11 needs it; L12 pins to My IP only)."
  type        = bool
  default     = true
}

variable "create_iam_role" {
  description = "Attach the L11 read-only role (S3, DynamoDB, CloudWatch Logs) as the private instance profile."
  type        = bool
  default     = false
}
