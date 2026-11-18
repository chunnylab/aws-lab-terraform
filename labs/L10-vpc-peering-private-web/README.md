# L10: VPC peering with a private-subnet web host

Terraform base for [lab L10](https://chunnylab.com/learn/aws-saa/L10-vpc-peering-private-web). Both networks and both instances exist from one apply; the peering itself is the lesson and stays yours.

## Terraform creates

| Resource | Detail |
|---|---|
| VPC `saa-l10-vpc-host` | 10.10.0.0/24, no internet gateway by design |
| Subnet and routing | `saa-l10-sub-private` 10.10.0.0/28 in ap-southeast-1a, `saa-l10-rt-private` with local routes only |
| VPC `saa-l10-vpc-client` | 10.20.0.0/24 with `saa-l10-igw` |
| Subnet and routing | `saa-l10-sub-public` 10.20.0.0/28 in ap-southeast-1b, `saa-l10-rt-public` with a default route |
| Security groups | `saa-l10-sg-host` with zero inbound rules; `saa-l10-sg-client` with SSH from EC2 Instance Connect |
| Instances | `saa-l10-ec2-host` serving HTML on port 80 via user data (works offline), `saa-l10-ec2-client` with a public IP, 2x t3.micro |

## You create (the lab)

The peering connection `saa-l10-pcx`, the route to 10.20.0.0/24 in `saa-l10-rt-private`, the route to 10.10.0.0/24 in `saa-l10-rt-public`, the port-80 inbound rule on `saa-l10-sg-host` scoped to the client, and the `curl` verify. The exam point is that peering needs routes on both sides plus the security group rule; none of that is pre-built.

## Apply

```bash
terraform init
terraform apply
```

The output prints `host_private_ip` and `client_private_ip` (the two values the lab page's "Values to note" table asks for), along with both VPC IDs, both route table IDs, and the client public IP.

## Cost and teardown

About 2x t3.micro plus one public IPv4 per hour. The lab needs two spare VPCs in the region (the default quota is five). When finished:

```bash
terraform destroy
```

Delete the peering connection in the console first if you created it outside Terraform; then destroy removes everything else.
