variable "aws_region" {
  description = "Region for the EBS encryption setting. IAM and Budgets are global."
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use. Empty string means the default credential chain."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address that receives the budget alerts. AWS sends a confirmation email first; alerts flow only after you confirm."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be an email address you read every day."
  }
}
