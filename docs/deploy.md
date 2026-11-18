# Deploying the labs

Every lab directory under `labs/` is a standalone Terraform root module. Pick a lab, point Terraform at your AWS account with one of the two paths below, and apply.

```bash
cd labs/L1-iam-guardrails
terraform init
terraform apply -var alert_email="you@example.com" -var aws_profile=my-profile
```

Variables every lab shares: `aws_region` (default `ap-southeast-1`, the region the lab pages pin) and `aws_profile` (default empty, meaning the default credential chain). L1 applies with just `alert_email`; the other labs also need a public key and your IP, and each lab README opens with its exact apply command.

## Path 1: long-lived access keys

The classic beginner setup. In the AWS console create an IAM user for yourself, create an access key for it, then:

```bash
aws configure          # paste Access Key ID, Secret Access Key, region ap-southeast-1
terraform apply
```

The keys land in `~/.aws/credentials` as the `default` profile, which Terraform picks up through the default credential chain. Rotate the key when done with the course.

## Path 2: IAM Identity Center (SSO)

The recommended setup, and the one to use when an organization manages lab accounts for you. It has two shapes; the commands at the terminal are the same.

### Shape A: Identity Center on your own account

You are the admin. In the account, open IAM Identity Center, enable it, create a user, create a permission set (see the table below), and assign the user to the account with that permission set. IAM Identity Center gives you a start URL like `https://d-xxxxxxxxxx.awsapps.com/start`. Note also the region you enabled Identity Center in; AWS calls it the SSO Region and it does not have to match `aws_region`.

### Shape B: an organization runs it for you

Someone else did the Shape A steps across the organization. You receive a start URL, a username, and a password. Nothing to set up on the AWS side.

### The terminal part, both shapes

```bash
aws configure sso
# Session name:          any label you like, e.g. chunnylab
# Start URL:             the URL from Shape A or from your admin
# SSO Region:            the region Identity Center lives in (not the lab region)
# Registration scopes:   accept the suggested sso:account:access
# CLI default client Region: ap-southeast-1
# CLI profile name:      e.g. chunnylab

aws sso login --profile chunnylab    # opens the browser, once per day or so
terraform apply -var aws_profile=chunnylab
```

`aws configure sso` writes the profile to `~/.aws/config`; `aws sso login` refreshes the temporary credentials. When apply suddenly fails with expired-token errors hours later, run `aws sso login` again.

### What the permission set needs per lab

The AWS managed policy `PowerUserAccess` allows everything except `iam:*`, `organizations:*`, and `account:*`. That covers the whole apply for L10 and L12. L11 and L1 need IAM added.

| Lab | Apply needs | The manual lab part needs |
|---|---|---|
| L1 | `budgets:*`, `ec2:*` (EBS setting) | `iam:*`, `ssm:*` for the roles, policy, and parameters you build by hand |
| L10 | PowerUserAccess is enough | PowerUserAccess |
| L11 | PowerUserAccess plus `iam:*` (the module creates the read-only role and instance profile) | PowerUserAccess |
| L12 | PowerUserAccess is enough | none, the lab is on your terminal |

For a lab account that exists to be a lab, attaching `AdministratorAccess` to the permission set is the pragmatic choice; the table above is for when you want tighter.

Two one-time settings only the account root user can do, both bite L1: turning on IAM user and role access to Billing information, and choosing the account name in IAM Identity Center. If Budgets says you lack permission, that billing toggle is the reason.

## State

State is local (`terraform.tfstate` inside the lab directory) and git-ignored. For a lab this is the right default: you apply, you learn, you destroy. If you repeat labs and want state to survive a lost laptop, drop this into the lab's `main.tf` and create the bucket first:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "aws-lab-terraform/L11/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "your-terraform-locks"
    encrypt        = true
  }
}
```

## Not covered: sandbox accounts

AWS Skill Builder sandbox accounts are deliberately out of scope here. Nobody has run these labs in one and recorded what works, and publishing an untested path in a beginner-facing repository would promise more than can be backed. If you run a lab in a sandbox and it works (or fails in a specific way), an issue describing it is welcome.
