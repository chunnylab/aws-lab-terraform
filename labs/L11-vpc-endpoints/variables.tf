variable "aws_region" {
  description = "Region for the lab. The lab page pins ap-southeast-1."
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use. Empty string means the default credential chain."
  type        = string
  default     = ""
}

variable "public_key" {
  description = "Your OpenSSH public key. Generate with ssh-keygen, then paste the contents of the .pub file. (run cat ~/.ssh/[your-public-key].pub)"
  type        = string

  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) ", var.public_key))
    error_message = "public_key must be OpenSSH material starting with ssh-rsa or ssh-ed25519. run cat ~/.ssh/[your-public-key].pub"
  }
}

variable "admin_cidr" {
  description = "Your IP as a /32 CIDR, allowed to SSH to the bastion. Find it with: curl -s https://checkip.amazonaws.com"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid IPv4 CIDR, e.g. 203.0.113.5/32."
  }
}
