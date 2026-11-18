# aws-lab-terraform

[![validate](https://github.com/chunnylab/aws-lab-terraform/actions/workflows/validate.yml/badge.svg)](https://github.com/chunnylab/aws-lab-terraform/actions/workflows/validate.yml)

Terraform bases for the AWS SAA labs at [chunnylab.com/learn/aws-saa](https://chunnylab.com/learn/aws-saa/). Each directory under `labs/` builds the boilerplate half of one lab page, so you start the actual lesson minutes after `terraform apply`, in your own account.

Terraform never builds the part the lab is testing. L10 ships two VPCs and no peering; L11 ships a private subnet with no route to the internet; L1 ships the account guardrails and none of the IAM. Each lab README carries the exact split: what Terraform creates, what you create.

## Labs

| Lab | Terraform creates | You create | Running cost |
|---|---|---|---|
| [L1 IAM guardrails](labs/L1-iam-guardrails/) | Zero-spend budget with email alert, EBS encryption by default | Auditor role, team roles, ABAC policy, parameters, switch-role tests | $0, apply once and keep |
| [L10 VPC peering](labs/L10-vpc-peering-private-web/) | Both VPCs, subnets, routing, security groups, both instances | Peering connection, routes on both sides, the port-80 rule | 2x t3.micro + 1 public IP |
| [L11 VPC endpoints](labs/L11-vpc-endpoints/) | Network, key pair, SG chaining, read-only role, both instances | S3 Gateway endpoint, then NAT + Interface endpoint stages | Stage 1: 2x t3.micro + 1 public IP; Stage 2 adds ~$0.07/hr |
| [L12 Bastion SSH jump](labs/L12-bastion-ssh-jump/) | The whole environment | The terminal work: ProxyJump, Agent Forwarding | 2x t3.micro + 1 public IP |

L2-L9 do not exist on the course site yet; each lab lands here as it is published, and the scenario tracks (W, DS, NF, and the rest) follow the same one-directory-per-lab scheme.

## Quickstart

```bash
git clone https://github.com/chunnylab/aws-lab-terraform.git
cd aws-lab-terraform/labs/L12-bastion-ssh-jump
terraform init
terraform apply \
  -var public_key="$(cat ~/.ssh/id_ed25519.pub)" \
  -var admin_cidr="$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32"
```

Authentication is covered in [docs/deploy.md](docs/deploy.md): classic access keys, or IAM Identity Center (SSO) end to end, with the permission set each lab needs.

## How this repository works

- One self-contained root module per lab. No wrapper, no orchestration: `cd` in and apply.
- Local state by default; `docs/deploy.md` shows an S3 backend if you want durable state.
- `modules/bastion-pair` is the only shared module. It serves L11 and L12, which need the identical base.
- CI runs `terraform fmt -check` and `terraform validate` on every directory plus a set of design guards (for example: the shared module must contain no NAT gateway, because L11 Stage 1 teaches through a timeout).
- Releases are semver tags with GitHub Releases; the course site changelog names each release.

## License

[MIT](LICENSE)
