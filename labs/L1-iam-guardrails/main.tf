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
      lab        = "L1-iam-guardrails"
      project    = "aws-lab-terraform"
      managed_by = "terraform"
    }
  }
}

# Equivalent of the console's "Zero spend budget" template: alert as soon as
# any real or forecast spend crosses 100 percent of one cent.
resource "aws_budgets_budget" "zero_spend" {
  name              = "saa-l1-zero-spend"
  budget_type       = "COST"
  limit_amount      = "0.01"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-01-01_00:00"

  notification {
    notification_type   = "ACTUAL"
    comparison_operator = "GREATER_THAN"
    threshold           = 100
    threshold_type      = "PERCENTAGE"

    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    notification_type   = "FORECASTED"
    comparison_operator = "GREATER_THAN"
    threshold           = 100
    threshold_type      = "PERCENTAGE"

    subscriber_email_addresses = [var.alert_email]
  }
}

# Regional EC2 setting: every new EBS volume in this Region is encrypted,
# whoever creates it. Existing volumes are untouched.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

output "budget_name" {
  description = "Budget name, for the re-run import line in the README."
  value       = aws_budgets_budget.zero_spend.name
}
