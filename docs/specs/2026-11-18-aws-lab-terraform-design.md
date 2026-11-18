# Design: aws-lab-terraform

Date: 2026-11-18
Status: awaiting approval

## Intent

One public repository, `chunnylab/aws-lab-terraform`, holding Terraform that provisions the boilerplate half of each lab on the Chunnylab AWS SAA course site (chunnylab.com/learn/aws-saa/). A learner with any personal AWS account runs `terraform apply` inside one lab directory and starts the lab's core task within minutes, skipping the click-heavy setup that teaches nothing. The repository also serves as a portfolio piece, so it ships with the hygiene a hiring reviewer expects: pinned versions, CI, cost notes, and release tags.

## Why now

The course site reached v0.31.0 with 24 scenario tracks and 4 topic labs, and its changelog shows topic labs landing weekly. Each new lab page asks the learner to build the same VPC, subnets, and instance scaffolding by hand before the actual lesson starts. That setup is the part worth automating, and doing it in Terraform makes the course usable from a clean account in one command.

## Goals

- One directory per lab page, deployable standalone with `terraform init && terraform apply`.
- Works against any personal AWS account, with two documented auth paths: long-lived access keys, and IAM Identity Center (SSO). The SSO path covers both a self-managed Identity Center on a personal account and an organization that creates SSO users for lab work, because the owner runs the second setup for his own labs.
- Free-tier-first cost posture, with per-lab estimated hourly cost and a destroy command in every lab README.
- Semver releases: git tag plus GitHub Release per meaningful change; each release gets an entry in the course site's `changelog.json`, and `about.html` links the repository.
- CI that runs `terraform fmt -check` and `terraform validate` on every push and pull request.

## Non-goals

- No wrapper, makefile, or orchestration layer on top of the per-lab directories.
- No remote state backend in the code. Local state is the default; `docs/deploy.md` shows an S3 backend snippet for learners who repeat labs and want durable state.
- No CI job that plans or applies against a real AWS account. Validation is credentials-free.
- No coverage of the 24 scenario tracks in the first release. The flat `labs/` scheme extends to them later without restructuring.

## Anti-goals

- Terraform must not do the lab for the learner. Every resource that carries the exam point stays manual; the split is written down in each lab README as "Terraform creates / you create".
- No hard-coded region, profile, or account ID anywhere in the code.

## Decisions from the owner

- Separate repository from the course site, following the existing `chunnylab-music-studio-infra` pattern. The current empty `terraform-aws-lab` directory is the seed.
- Learners deploy with their own personal AWS accounts, not accounts the project provisions.
- Repository structure leaves room for every track; the first release covers the L-series topic labs.
- Name built from the tokens aws-lab-terraform, dropping "saa", under the chunnylab organization. Arranged as `chunnylab/aws-lab-terraform`.

## Facts the design rests on

- Only four L-series lab pages exist: L1 (IAM guardrails), L10 (VPC peering), L11 (VPC endpoints), L12 (bastion SSH jump). L2 through L9 have never been built; they enter this repository when they appear on the site.
- All four lab pages pin ap-southeast-1.
- L11 and L12 need an essentially identical base: one VPC 10.0.0.0/16, public and private /24 subnets in one AZ, an IGW, two route tables, a key pair, two chained security groups, and 2x t3.micro Amazon Linux 2023. L12 is L11 minus the IAM role and endpoints.
- L10 uses two small VPCs (10.10.0.0/24 host, no IGW; 10.20.0.0/24 client, with IGW), /28 subnets across 1a and 1b.
- The course site's `build.py` refuses to ship a changed page without a matching `changelog.json` entry, so website versioning needs no new mechanism, only entries.

## Repository layout

```
labs/
  L1-iam-guardrails/
  L10-vpc-peering-private-web/
  L11-vpc-endpoints/
  L12-bastion-ssh-jump/
modules/
  bastion-pair/
docs/
  deploy.md
.github/workflows/validate.yml
README.md
LICENSE (MIT)
```

Each directory under `labs/` is a self-contained root module: `main.tf`, `variables.tf`, `outputs.tf`, `README.md`. Directory names match the site's page slugs so a lab page maps to exactly one path.

## Per-lab provisioning split

| Lab | Terraform creates | Learner creates by hand | Est. hourly cost |
|---|---|---|---|
| L1 | Zero-spend AWS Budget with email notification (a required `alert_email` variable; the README explains the one-time confirmation email), EBS encryption-by-default (the keep-forever guardrails) | Both IAM roles, the ABAC policy, the tagged SSM parameters, switch-role tests | $0 |
| L10 | Both VPCs, subnets, route tables, client IGW, security group shells, 2x t3.micro with the host's user-data web server | The peering connection, routes in both route tables, the host's port-80 inbound rule, the curl verify | 2x t3.micro + 1 public IPv4 |
| L11 | VPC, subnets, route tables, IGW, key pair, SG chaining, the ReadOnly IAM role as instance profile, 2x t3.micro | S3 Gateway endpoint, then NAT gateway + EIP + private 0/0 route + CloudWatch Logs Interface endpoint (Stage 2) | Stage 1: 2x t3.micro + 1 public IPv4. Stage 2 adds roughly $0.07/hr |
| L12 | Everything: full base from the shared module, key pair from the learner's public key | All terminal work: ssh-add, ProxyJump, Agent Forwarding, the troubleshooting matrix | 2x t3.micro + 1 public IPv4 |

Two protections are deliberate. The `bastion-pair` module ships with no NAT gateway and no 0/0 route in the private route table, because L11 Stage 1 teaches by watching `aws s3 ls` time out first. And L10's host security group starts with zero inbound rules, because adding the rule is the exam point.

## Modules

One shared module: `modules/bastion-pair` (VPC, subnets, IGW, route tables, key pair, SG chaining, 2x t3.micro, optional IAM role). Used by L11 and L12. L10 stays a self-contained root module; parameterizing one module to also fit two tiny isolated VPCs would cost more than the 60 lines it saves. New modules appear only when a second lab needs the same code.

## Auth and deploy paths (docs/deploy.md)

The provider block reads `aws_profile` and `aws_region` variables, with `ap-southeast-1` as the default region, and stamps every resource with `default_tags` (lab, project, managed_by). The two paths:

1. Access keys: `aws configure`, then apply. The path most beginners already have.
2. IAM Identity Center (SSO): `aws configure sso`, `aws sso login --profile <name>`, then `terraform apply -var aws_profile=<name>`. The doc walks through both shapes of this path: a learner enabling Identity Center on their own account, and an organization admin creating SSO users and permission sets for lab work, which is the owner's own setup and the part he wants to learn. A table lists the minimum service permissions a permission set needs per lab (VPC, EC2, IAM, Budgets, SSM, and so on), because apply fails halfway without them.

The AWS Skill Builder sandbox is deliberately out of scope: it has not been verified, and publishing an untested path in a repository aimed at beginners would promise more than the docs can back. It can be added after someone runs a lab in one for real.

Every lab README carries a footer with estimated cost and the destroy command. L1's footer is qualified, because the lab page itself says to keep the budget and the EBS setting for later labs: its README tells the learner to keep them and shows the destroy command only as the way to remove them for good. A second run of L1 with fresh state collides on the existing budget name, so the README shows the matching `terraform import` line instead of letting apply fail.

## Versioning

- Repository: semver git tags (`v0.1.0` = L1, L10, L11, L12) with GitHub Releases; a release notes which labs were added or changed.
- Website: each release adds one entry to the course site's `changelog.json` naming the release tag, which `build.py` already enforces and renders at `changelog.html`. `about.html` gains the repository link. Per-lab page links into the repository are a later, optional step once there is more than one release to point at.

## CI

A single GitHub Actions workflow: `terraform fmt -check` and `terraform validate` across every lab directory, on push and pull request. Validation needs no AWS credentials because the provider reads only variables. README shows the badge.

## Pinned versions

- Terraform `>= 1.6.0`
- AWS provider `~> 6.0` (latest 6.73.0 today)
- Amazon Linux 2023 AMI resolved through the SSM public parameter, never hard-coded.

## Left to the builder

- Exact security group starting rules, read off each lab page so the wording matches.
- User-data script for the L10 host, copied from the lab page.
- Per-lab README content: the creates-split table, cost lines, destroy step.
- Local rename of the working directory to `aws-lab-terraform`, `git init`, GitHub repository creation under the chunnylab organization, first push, and tag `v0.1.0`.
- The `about.html` link and first `changelog.json` entry in the course site repository.
