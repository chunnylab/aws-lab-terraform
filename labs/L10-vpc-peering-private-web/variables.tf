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
