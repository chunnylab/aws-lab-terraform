# L11: VPC endpoints (Gateway and Interface)

Terraform base for [lab L11](https://chunnylab.com/learn/aws-saa/L11-vpc-endpoints). The base stops exactly where the lesson starts.

## Terraform creates

| Resource | Detail |
|---|---|
| VPC `saa-l11-vpc` | 10.0.0.0/16, DNS support and hostnames on |
| Subnets | public 10.0.1.0/24 and private 10.0.2.0/24, both in ap-southeast-1a |
| Routing | IGW, public route table with a default route, private route table with local routes only |
| IAM role | `saa-l11-role-private` as instance profile: S3, DynamoDB, CloudWatch Logs read-only |
| Key pair and SGs | `saa-l11-key`; bastion SG (SSH from your IP and EC2 Instance Connect), private SG (SSH from the bastion SG) |
| Instances | bastion (public IP) and private host, 2x t3.micro Amazon Linux 2023 |

## You create (the lab)

Stage 1: run `aws s3 ls` from the private host and watch it time out, then create the S3 Gateway endpoint and watch the prefix-list route appear. Stage 2: add the NAT gateway with an Elastic IP, the private default route, and the CloudWatch Logs Interface endpoint with private DNS, then compare the DynamoDB path with `getent`.

The base ships with no NAT and no private default route on purpose: the Stage 1 timeout is the lesson, and Terraform pre-creating them would delete it.

## Apply

```bash
terraform init
terraform apply \
  -var public_key="$(cat ~/.ssh/id_ed25519.pub)" \
  -var admin_cidr="$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32"
```

The output prints `private_route_table_id` and `private_subnet_id`, the two IDs Stage 2 asks for.

## Cost and teardown

Stage 1 runs on 2x t3.micro plus one public IPv4. Stage 2 resources you create in the console add roughly $0.07 per hour (NAT gateway, Elastic IP while attached, Interface endpoint); the lab page shows how to stop after Stage 1. Delete your Stage 2 resources first, then:

```bash
terraform destroy -var public_key="ssh-ed25519 AAAA dummy" -var admin_cidr="203.0.113.5/32"
```

Stage 2 resources are console-created, so Terraform does not know about them; removing them is part of the lab's cleanup steps.
