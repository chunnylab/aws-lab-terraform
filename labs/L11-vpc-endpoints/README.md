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
| S3 bucket | `saa-l11-assets-*` (private, `force_destroy = true`) with `sample.svg` for `aws s3 ls` / `aws s3 cp` verification |
| VPC endpoints | S3 Gateway `saa-l11-vpce-s3`, DynamoDB Gateway `saa-l11-vpce-dynamodb`, CloudWatch Logs Interface `saa-l11-vpce-cw` (private DNS on, SG `saa-l11-sg-vpce` allows 443 from the private SG) |
| DynamoDB | table `saa-l11-items` with one item (`id = hello from hangyao with dynamoDB`) |
| CloudWatch Logs | log group `/saa-l11/lab`, stream `sample` |

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

The output prints `bastion_public_ip` and `private_instance_private_ip` (for the "Values to note" table), plus `public_subnet_id`, `private_subnet_id`, and `private_route_table_id` for Stage 2. Because Terraform registers your existing public key as `saa-l11-key` instead of generating a new `.pem` download in the console, use your matching local private key (`~/.ssh/id_ed25519`) wherever the lab page writes `saa-l11-key.pem`.

## Cost and teardown

Stage 1 runs on 2x t3.micro plus one public IPv4. Stage 2 resources you create in the console add roughly $0.07 per hour (NAT gateway, Elastic IP while attached, Interface endpoint); the lab page shows how to stop after Stage 1. Delete your console-created resources first (`saa-l11-vpce-s3`, and if you ran Stage 2: `saa-l11-vpce-cw`, `saa-l11-sg-vpce`, `saa-l11-nat`, and its Elastic IP), then:

```bash
terraform destroy -var public_key="ssh-ed25519 AAAA dummy" -var admin_cidr="203.0.113.5/32"
```

Console-created endpoints, security groups, and NAT gateways are outside Terraform state; removing them first avoids dependency errors when Terraform deletes the route tables, security groups, and VPC.

## Test the endpoints

From the bastion, SSH to the private host (use `ssh -A` or copy the key), then:

```bash
export AWS_DEFAULT_REGION=ap-southeast-1
aws s3 ls                                                   # S3 Gateway
aws dynamodb scan --table-name saa-l11-items                # DynamoDB Gateway
aws logs describe-log-groups --log-group-name-prefix /saa-l11   # Logs Interface
getent hosts logs.ap-southeast-1.amazonaws.com              # expect 10.0.2.x (endpoint ENI)
getent hosts dynamodb.ap-southeast-1.amazonaws.com          # expect a public IP, routed via the prefix list
```

The private subnet has no NAT, so success proves the traffic stays on the AWS network. To see the negative case, delete one endpoint in the console and rerun its command: it times out.

aws s3 ls
    aws dynamodb scan --table-name saa-l11-items
    aws logs describe-log-groups --log-group-name-prefix /saa-l11
    getent hosts logs.ap-southeast-1.amazonaws.com       # ควรได้ 10.0.2.x (IP ของ endpoint ENI)
    getent hosts dynamodb.ap-southeast-1.amazonaws.com   # ควรได้ public IP ที่วิ่งผ่าน prefix-list route
