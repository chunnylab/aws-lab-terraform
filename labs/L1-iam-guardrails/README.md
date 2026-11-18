# L1: Permissions and guardrails (base)

Terraform base for [lab L1](https://chunnylab.com/learn/aws-saa/L1-iam-guardrails). IAM is the lesson here, so Terraform creates only the two account-level guardrails the lab says to keep forever; every role and policy is yours to build.

## Terraform creates

| Resource | Detail |
|---|---|
| Budget `saa-l1-zero-spend` | Monthly cost budget of $0.01, alerts at 100 percent actual and forecast, delivered to `alert_email` |
| EBS encryption by default | Regional EC2 setting: every new EBS volume in the Region is encrypted |

## You create (the lab)

The auditor role `saa-l1-auditor`, the team roles `saa-l1-dev-alpha` (and optionally dev-beta), the ABAC policy `saa-l1-abac-team`, the Standard parameters `/saa-l1/alpha/db-host` and `/saa-l1/beta/db-host`, and the Switch-role tests.

## Prerequisites

Your credentials need Budgets and EC2 permissions (see `docs/deploy.md`). If the account has never used Budgets, IAM user and role access to Billing must be turned on by the root user first. Apply as an IAM user or Identity Center user, never as the root user: Switch-role, which the lab depends on, does not exist for root.

## Apply

```bash
terraform init
terraform apply -var alert_email="you@example.com"
```

AWS sends one confirmation email to `alert_email`. Budget alerts flow only after you open it and confirm the subscription.

## Keep these, do not destroy

The lab page is explicit: the zero-spend budget and EBS encryption by default are free guardrails that stay on for every later lab. This directory is apply-once. The destroy command exists only for removing them for good, for example when you retire the account:

```bash
terraform destroy -var alert_email="you@example.com"
```

## Applying again on an account that already has the budget

Fresh Terraform state collides with the existing budget name. Import it instead of failing:

```bash
terraform import -var alert_email="you@example.com" \
  aws_budgets_budget.zero_spend \
  "$(aws sts get-caller-identity --query Account --output text):saa-l1-zero-spend"
```
