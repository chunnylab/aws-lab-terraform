#!/usr/bin/env bash
# Design guards for this repository. The workflow calls this script, and it
# runs locally with `bash scripts/guards.sh`. Every check must exit non-zero
# on violation: bash errexit does not fire for `!`-inverted pipelines, so
# each check is written as an explicit if-then-exit.
set -uo pipefail

fail() { echo "GUARD VIOLATION: $1" >&2; exit 1; }

TF=(--include='*.tf' --exclude-dir=.terraform)

# L11 Stage 1 teaches through a timeout: the shared module must never add a
# NAT gateway, and only the public route table may carry a default route.
grep -rq "nat_gateway" modules/bastion-pair "${TF[@]}" && fail "nat_gateway found in modules/bastion-pair"
test "$(grep -r 'destination_cidr_block = "0.0.0.0/0"' modules/bastion-pair/main.tf | wc -l)" -eq 1 \
  || fail "modules/bastion-pair must have exactly one default route (the public IGW route)"

# AMIs resolve through SSM, never a hard-coded id. Match an actual AMI id
# (ami- + 8..17 hex chars), not the SSM parameter path, which also contains
# the substring "ami-".
grep -rqE 'ami-[0-9a-f]{8,17}' labs/ modules/ "${TF[@]}" && fail "hard-coded AMI id found"

# Region defaults live in variables.tf only.
grep -rqE 'region[[:space:]]*=[[:space:]]*"ap-' --include='main.tf' labs/ modules/ && fail "hard-coded region in a main.tf"

# The L10 host security group starts with zero inbound rules; the port-80
# rule is the exam point and belongs to the learner.
sed -n '/saa-l10-sg-host/,/^}/p' labs/L10-vpc-peering-private-web/main.tf | grep -q ingress \
  && fail "saa-l10-sg-host must not declare inbound rules"

# Security groups in Terraform drop the AWS default allow-all egress when no
# egress is declared, which silently blocks the labs' core tasks. Every
# network-bearing directory must declare its egress rules explicitly.
grep -q "aws_vpc_security_group_egress_rule" modules/bastion-pair/main.tf \
  || fail "bastion-pair declares no egress rules (deny-all outbound)"
grep -q "aws_vpc_security_group_egress_rule" labs/L10-vpc-peering-private-web/main.tf \
  || fail "L10 declares no egress rules (deny-all outbound)"

# L1 budget alerts need a validated email variable.
grep -q "validation" labs/L1-iam-guardrails/variables.tf \
  || fail "L1 alert_email variable lacks a validation block"

echo "guards: all checks passed"
