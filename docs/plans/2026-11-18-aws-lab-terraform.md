# aws-lab-terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish `chunnylab/aws-lab-terraform`, a public Terraform repo whose four lab directories provision the boilerplate half of labs L1, L10, L11, L12 from chunnylab.com/learn/aws-saa/, tagged v0.1.0 and linked from the course site.

**Architecture:** One self-contained root module per lab page under `labs/`, one shared module `modules/bastion-pair` serving L11 and L12, local state, credentials-free CI (fmt + validate + guard greps), semver releases mapped to the site's existing `changelog.json`.

**Tech Stack:** Terraform >= 1.6 (installed 1.16.1), AWS provider ~> 6.0, GitHub Actions, gh CLI (authed as chunnytechmate), site repo `~/projects/chunnylab-aws-saa` built by `build.py`.

**Spec:** `docs/specs/2026-11-18-aws-lab-terraform-design.md` (in this repo). Executors read both.

## Global Constraints

- Terraform `required_version >= 1.6.0`; AWS provider `~> 6.0`.
- No hard-coded region, profile, account ID, or AMI id anywhere. Region defaults live only as variable defaults (`ap-southeast-1`). AMI resolves via SSM parameter `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`.
- Every resource carries `default_tags`: `lab = "<slug>"`, `project = "aws-lab-terraform"`, `managed_by = "terraform"`.
- Resource names follow the lab pages: `saa-l1-*`, `saa-l10-*`, `saa-l11-*`, `saa-l12-*`.
- The `bastion-pair` module must never contain a NAT gateway or a 0.0.0.0/0 route in the private route table (L11 Stage 1 depends on `aws s3 ls` timing out).
- All authored prose (READMEs, docs, commit messages) follows Chunny Writing Style: no U+2014 em dash, direct, concrete. Run `chunny-style <file>` after writing prose files and fix all errors.
- Commit messages end with `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- License: MIT.
- Labs pages (source of exact values) live at `/home/chunny-techmate/projects/chunnylab-aws-saa/dist/learn/aws-saa/L*.html`.

## Review Focus

1. Private subnet egress accidentally allowed in `bastion-pair` (NAT or 0/0 private route) breaks L11 Stage 1. Guard: CI grep asserts no `nat_gateway` in the module and exactly one `0.0.0.0/0` (the public RT's IGW route). Task 2.
2. Empty or malformed `alert_email` creates a budget that never notifies. Guard: the `validation` block (email regex) on the variable in `labs/L1-iam-guardrails/variables.tf`, asserted by a CI grep (variable validation runs at plan time, not validate time, so the block's presence is the automatable gate). Task 6 and Task 8.
3. Hard-coded AMI id breaks other regions. Guard: CI grep rejects `ami-` in `labs/` and `modules/`. Task 2 onward, enforced in Task 8.
4. L10 host security group created with an ingress rule steals the exam point. Guard: `sed` range over the `saa-l10-sg-host` resource block must contain no `ingress`. Task 5.
5. Hard-coded `region = "ap-..."` outside a variables.tf default. Guard: CI grep over `main.tf`/`provider.tf` files. Task 8.

---

### Task 1: Rename directory, git init, scaffold

**Files:**
- Rename: `~/projects/terraform-aws-lab` -> `~/projects/aws-lab-terraform`
- Create: `.gitignore`, `LICENSE`, stub `README.md`

**Interfaces:**
- Produces: repo root at `/home/chunny-techmate/projects/aws-lab-terraform` containing `docs/` (spec + this plan), git history started. All later tasks use this absolute path.

- [ ] **Step 1: Rename and init**

```bash
mv ~/projects/terraform-aws-lab ~/projects/aws-lab-terraform
cd ~/projects/aws-lab-terraform && git init
```

After this task every path is absolute under `/home/chunny-techmate/projects/aws-lab-terraform`. If a tool refuses the new path, work on and note the fallback at handoff.

- [ ] **Step 2: Write `.gitignore`**

`*.tfstate`, `*.tfstate.*`, `.terraform/`, `.terraform.lock.hcl` is NOT ignored (commit it), `crash.log`, `*.tfvars`, `!*.tfvars.example`, `override.tf`

- [ ] **Step 3: Write `LICENSE`** (MIT, copyright 2026 Chunnapan Sukontasup)

- [ ] **Step 4: Write stub `README.md`** (title + one line; Task 8 replaces it)

- [ ] **Step 5: Verify**

Run: `cd ~/projects/aws-lab-terraform && git status --short`
Expected: only untracked `.gitignore`, `LICENSE`, `README.md`, `docs/`

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: repo scaffold (MIT, gitignore)
Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

### Task 2: modules/bastion-pair

**Files:**
- Create: `modules/bastion-pair/{main.tf,variables.tf,outputs.tf,versions.tf}`

**Interfaces:**
- Consumes: nothing.
- Produces (exact): variables `name_prefix string`, `vpc_cidr string default "10.0.0.0/16"`, `az string default "ap-southeast-1a"`, `aws_region string default "ap-southeast-1"` (used for the EIC prefix list data source), `public_key string` (required), `admin_cidr string` (required, `/32` or CIDR), `enable_eic_prefix bool default true`, `create_iam_role bool default false`. Outputs: `vpc_id`, `public_subnet_id`, `private_subnet_id`, `private_route_table_id`, `sg_bastion_id`, `sg_private_id`, `bastion_public_ip`, `private_instance_id`, `key_pair_name`.

- [ ] **Step 1: Write `versions.tf` and `variables.tf`**

`versions.tf`: required_version `>= 1.6.0`, provider `hashicorp/aws ~> 6.0`. Variables per Interfaces block above.

- [ ] **Step 2: Write `main.tf`**

Resources (names prefixed `${name_prefix}-`):
- `aws_vpc` (CIDR, dns_support + dns_hostnames), public subnet (`10.0.1.0/24`-style: derive as cidrsubnet(var.vpc_cidr, 8, 1)), private subnet (cidrsubnet(var.vpc_cidr, 8, 2)), both in `var.az`
- `aws_internet_gateway`, public RT with `0.0.0.0/0 -> IGW`, private RT with no routes (local only)
- `aws_key_pair` from `var.public_key` (name `${name_prefix}-key`)
- `aws_security_group` bastion: ingress 22 from `var.admin_cidr` and, when `enable_eic_prefix`, from the EC2 Instance Connect managed prefix list (`data.aws_prefix_list`, name `com.amazonaws.${var.aws_region... }` needs region input: add variable `aws_region string default "ap-southeast-1"` to the module and pass it; provider region comes from the caller)
- `aws_security_group` private: ingress 22 sourced from the bastion SG id (SG chaining)
- 2x `aws_instance` t3.micro AL2023 (AMI via `data.aws_ssm_parameter`), bastion in public subnet `associate_public_ip_address = true`, private instance no public IP, both keyed
- when `create_iam_role`: role `${name_prefix}-role-private` (trust ec2) with the three ReadOnly managed policies the L11 page names (S3, DynamoDB, CloudWatch Logs ReadOnly), instance profile, attached to the private instance
- `default_tags` live in the caller's provider block, not here

- [ ] **Step 3: Write `outputs.tf`** per Interfaces block

- [ ] **Step 4: Verify**

```bash
cd ~/projects/aws-lab-terraform/modules/bastion-pair
terraform fmt -check && terraform init -backend=false && terraform validate
grep -c nat_gateway main.tf   # expected: 0
grep -c "0.0.0.0/0" main.tf   # expected: 1
```

- [ ] **Step 5: Commit** `feat: bastion-pair module (VPC, SG chaining, 2x t3.micro, no NAT by design)` + trailer

### Task 3: labs/L12-bastion-ssh-jump

**Files:**
- Create: `labs/L12-bastion-ssh-jump/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`

**Interfaces:**
- Consumes: `modules/bastion-pair` (Task 2 interface).
- Produces: root module deployable with variables `aws_region` (default `ap-southeast-1`), `aws_profile` (default `""`), `public_key`, `admin_cidr`.

- [ ] **Step 1: Write the root module**

Provider block: `region = var.aws_region`, `profile = var.aws_profile != "" ? var.aws_profile : null`, `default_tags` trio with `lab = "L12-bastion-ssh-jump"`. Call the module with `name_prefix = "saa-l12"`, `enable_eic_prefix = false` (L12 page: bastion SSH is from My IP only), `create_iam_role = false`. Outputs: `bastion_public_ip`, `private_instance_id`.

- [ ] **Step 2: Write `README.md`**

Structure: what this provisions (full base; the lab is entirely terminal work), the creates-split table (Terraform creates everything / you do all SSH work: ssh-add, ProxyJump, Agent Forwarding), estimated cost (2x t3.micro + 1 public IPv4), destroy footer, link to the lab page.

- [ ] **Step 3: Verify**

```bash
cd ~/projects/aws-lab-terraform/labs/L12-bastion-ssh-jump
terraform fmt -check && terraform init -backend=false && terraform validate
chunny-style README.md
```

- [ ] **Step 4: Commit** `feat: L12 lab base (bastion pair, full provisioning)` + trailer

### Task 4: labs/L11-vpc-endpoints

**Files:**
- Create: `labs/L11-vpc-endpoints/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`

**Interfaces:**
- Consumes: `modules/bastion-pair` with `name_prefix = "saa-l11"`, `create_iam_role = true`, `enable_eic_prefix = true`.
- Produces: variables `aws_region`, `aws_profile`, `public_key`, `admin_cidr`. Outputs: everything the learner needs for Stage 2: `vpc_id`, `private_subnet_id`, `private_route_table_id`, `sg_private_id`, `bastion_public_ip`, `private_instance_id`.

- [ ] **Step 1: Write the root module** (same provider pattern, `lab = "L11-vpc-endpoints"`; pass-through outputs above)

- [ ] **Step 2: Write `README.md`**

Creates-split: Terraform creates the network + role + instances; you create the S3 Gateway endpoint (Stage 1), then NAT + EIP + private 0/0 route + CloudWatch Logs Interface endpoint (Stage 2). State explicitly that the base ships with no NAT and no private 0/0 route so the Stage 1 `aws s3 ls` timeout happens as the page intends. Cost: Stage 1 2x t3.micro + 1 public IPv4; Stage 2 adds roughly $0.07/hr, destroy footer noting Stage 2 resources are console-created and removed with the lab, not by Terraform.

- [ ] **Step 3: Verify** (same as Task 3, dir `L11-vpc-endpoints`)

- [ ] **Step 4: Commit** `feat: L11 lab base (gateway/interface endpoint stages stay manual)` + trailer

### Task 5: labs/L10-vpc-peering-private-web

**Files:**
- Create: `labs/L10-vpc-peering-private-web/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`

**Interfaces:**
- Consumes: nothing shared (self-contained by design).
- Produces: variables `aws_region`, `aws_profile`, `admin_cidr`. Outputs: `host_vpc_id`, `client_vpc_id`, `host_route_table_id`, `client_route_table_id`, `client_instance_public_ip`, `host_instance_id`.

- [ ] **Step 1: Write the root module**

Two VPCs exactly as the page pins them: host `saa-l10-vpc-host` 10.10.0.0/24, private /28 subnet in `ap-southeast-1a`, local-only RT, no IGW; client `saa-l10-vpc-client` 10.20.0.0/24, public /28 in `ap-southeast-1b`, IGW + 0/0 route. SGs: `saa-l10-sg-host` with NO ingress blocks; client SG ingress 22 from the EIC prefix list. 2x t3.micro AL2023, no key pair (EIC), client `associate_public_ip_address = true`, host no public IP. Host user-data: copy the `python3 -m http.server` systemd unit verbatim from the L10 page (source: `/home/chunny-techmate/projects/chunnylab-aws-saa/dist/learn/aws-saa/L10-vpc-peering-private-web.html`, Task 3 section). Provider pattern as Task 3, `lab = "L10-vpc-peering-private-web"`.

- [ ] **Step 2: Write `README.md`** (creates-split: peering, both routes, host port-80 inbound, curl verify are yours; cost; destroy)

- [ ] **Step 3: Verify**

```bash
cd ~/projects/aws-lab-terraform/labs/L10-vpc-peering-private-web
terraform fmt -check && terraform init -backend=false && terraform validate
sed -n '/saa-l10-sg-host/,/^}/p' main.tf | grep -q ingress && echo VIOLATION || echo OK
chunny-style README.md
```

- [ ] **Step 4: Commit** `feat: L10 lab base (two VPCs, no peering by design)` + trailer

### Task 6: labs/L1-iam-guardrails

**Files:**
- Create: `labs/L1-iam-guardrails/{main.tf,variables.tf,outputs.tf,versions.tf,README.md}`

**Interfaces:**
- Consumes: nothing.
- Produces: variables `aws_region`, `aws_profile`, `alert_email string` with `validation` regex on a standard email shape. Output: `budget_name`.

- [ ] **Step 1: Write the root module**

Two resources. `aws_budgets_budget` named per the L1 page Task 1 (open `/home/chunny-techmate/projects/chunnylab-aws-saa/dist/learn/aws-saa/L1-iam-guardrails.html`, copy the exact name, limit amount, budget type, time unit, and notification thresholds; subscriber = `var.alert_email`). `aws_ebs_encryption_by_default` set true. Provider pattern as Task 3, `lab = "L1-iam-guardrails"`.

- [ ] **Step 2: Write `README.md`**

Creates-split: Terraform creates the two keep-forever guardrails (budget with email alert; explain the one-time confirmation email AWS sends and that alerts flow only after confirming); you create both roles, the ABAC policy, the tagged parameters, and switch-role tests. Qualified footer per spec: keep these; destroy command shown only as the way to remove them for good. Include the re-run collision line: `terraform import aws_budgets_budget.<logical> <budget-name>`.

- [ ] **Step 3: Verify**

```bash
cd ~/projects/aws-lab-terraform/labs/L1-iam-guardrails
terraform fmt -check && terraform init -backend=false && terraform validate
grep -q "validation" variables.tf && echo OK
chunny-style README.md
```

- [ ] **Step 4: Commit** `feat: L1 guardrail base (zero-spend budget with email, EBS encryption)` + trailer

### Task 7: docs/deploy.md

**Files:**
- Create: `docs/deploy.md`

- [ ] **Step 1: Write it**

Two auth paths per spec: (1) access keys via `aws configure`; (2) IAM Identity Center end to end: what the organization admin does (enable Identity Center, create the user, permission set, assignment), what the learner does (`aws configure sso`, `aws sso login --profile`, `terraform apply -var aws_profile=...`), covering both a self-managed personal-account setup and the owner's org-managed SSO users. A per-lab minimum permissions table: L1 needs budgets + account settings + IAM; L10/L11/L12 need EC2 + VPC + SSM parameter read + (L11) IAM roles. Local state default; a commented S3 backend snippet for repeaters. Skill Builder sandbox explicitly out of scope with one line saying why.

- [ ] **Step 2: Verify** `chunny-style docs/deploy.md` (0 errors)

- [ ] **Step 3: Commit** `docs: deploy paths (access keys, IAM Identity Center, permission table)` + trailer

### Task 8: Root README + CI workflow

**Files:**
- Create: `.github/workflows/validate.yml`
- Modify: `README.md` (replace stub)

- [ ] **Step 1: Write `validate.yml`**

On push and PR: checkout, `hashicorp/setup-terraform@v3`, then loop `for d in modules/bastion-pair labs/*; do (cd "$d" && terraform init -backend=false && terraform fmt -check && terraform validate); done`, plus the Review Focus guards: no `nat_gateway` under `modules/bastion-pair`, exactly one `0.0.0.0/0` in `modules/bastion-pair/main.tf`, no `ami-` under `labs/` or `modules/`, no `region = "ap-` outside `variables.tf`, no `ingress` inside the `saa-l10-sg-host` block, and `validation` present in `labs/L1-iam-guardrails/variables.tf`.

- [ ] **Step 2: Write root `README.md`**

Title, CI badge, what this is (Terraform bases for the Chunnylab AWS SAA labs), the four-lab table (lab, Terraform creates, you create, cost), quickstart (`git clone`, `cd labs/L11-vpc-endpoints`, `terraform init`, `terraform apply`), auth pointer to `docs/deploy.md`, roadmap line (L2-L9 and scenario tracks land as the site publishes them), versioning (tags + Releases), MIT.

- [ ] **Step 3: Verify**

```bash
cd ~/projects/aws-lab-terraform && chunny-style README.md
```

Workflow correctness is proven by the first push in Task 9 (`gh run list` must be green), not by a local YAML parse.

- [ ] **Step 4: Commit** `feat: CI (fmt, validate, guard greps) and root README` + trailer

### Task 9: GitHub repo, push, v0.1.0 release

**Interfaces:**
- Consumes: everything committed in Tasks 1-8.

- [ ] **Step 1: Create the public repo and push**

```bash
cd ~/projects/aws-lab-terraform
gh repo create chunnylab/aws-lab-terraform --public \
  --description "Terraform bases for the Chunnylab AWS SAA labs: one directory per lab, apply and start the lesson." \
  --source . --push
```

- [ ] **Step 2: Tag and release**

```bash
git tag v0.1.0 && git push origin v0.1.0
gh release create v0.1.0 --title "v0.1.0" --notes "First release: Terraform bases for L1 (IAM guardrails), L10 (VPC peering), L11 (VPC endpoints), L12 (bastion SSH jump). Docs cover access-key and IAM Identity Center deploys."
```

- [ ] **Step 3: Verify** `gh run list --repo chunnylab/aws-lab-terraform --limit 1` shows the workflow passing; fix and push if red.

### Task 10: Course site entry + About link

**Files:**
- Modify: `/home/chunny-techmate/projects/chunnylab-aws-saa/changelog.json` (new first entry)
- Modify: `/home/chunny-techmate/projects/chunnylab-aws-saa/about.html` (repository link)

- [ ] **Step 1: Add the changelog entry**

New first object: `"version": "0.32.0", "date": "2026-11-18", "level": "minor"`, notes naming the repo and release: published aws-lab-terraform v0.1.0 with Terraform bases for L1, L10, L11, L12, deploy paths for access keys and IAM Identity Center, and the About link to the repository.

- [ ] **Step 2: Add the About link**

In `about.html`, add the GitHub repository link near the existing chunnylab.com mention, matching the page's link markup.

- [ ] **Step 3: Verify**

```bash
cd /home/chunny-techmate/projects/chunnylab-aws-saa && python3 build.py
```

Expected: clean run; the version check ties `changelog.html` to the new 0.32.0 entry and reports no problems.

- [ ] **Step 4: Commit** in the site repo: `feat: aws-lab-terraform v0.1.0 entry and About link` + trailer. Do not push or deploy the site without asking.
