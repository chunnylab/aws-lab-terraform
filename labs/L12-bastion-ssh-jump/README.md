# L12: Bastion SSH jump from your terminal

Terraform base for [lab L12](https://chunnylab.com/learn/aws-saa/L12-bastion-ssh-jump). This lab is entirely terminal work, so Terraform builds the whole environment and the lesson is yours.

## Terraform creates

| Resource | Detail |
|---|---|
| VPC `saa-l12-vpc` | 10.0.0.0/16, DNS support and hostnames on |
| Subnets | public 10.0.1.0/24 and private 10.0.2.0/24, both in ap-southeast-1a |
| Routing | IGW, public route table with a default route, private route table with local routes only |
| Key pair | `saa-l12-key`, from your `public_key` variable |
| Security groups | bastion: TCP 22 from `admin_cidr` only; private: TCP 22 from the bastion SG (SG chaining, not an IP) |
| Instances | bastion (public IP) and private host, 2x t3.micro Amazon Linux 2023 |

## You create (the lab)

Everything on your own terminal: `chmod 400`, `ssh-add`, ProxyJump with `ssh -J`, Agent Forwarding with `ssh -A`, and the troubleshooting matrix on the lab page.

## Apply

```bash
terraform init
terraform apply \
  -var public_key="$(cat ~/.ssh/id_ed25519.pub)" \
  -var admin_cidr="$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32"
```

The apply output prints `bastion_public_ip` and `private_instance_private_ip` (the two values the lab page's "Values to note" table asks for). Because Terraform registers your existing public key as `saa-l12-key` instead of generating a `.pem` download in the console, pass your matching local private key (`~/.ssh/id_ed25519`) to `ssh -i` and `ssh-add` wherever the lab page writes `~/Downloads/saa-l12-key.pem`.

## Cost and teardown

About 2x t3.micro plus one public IPv4 per hour while it runs. When finished:

```bash
terraform destroy -var public_key="ssh-ed25519 AAAA dummy" -var admin_cidr="203.0.113.5/32"
```

The variable values in destroy only need to pass validation; the key pair is destroyed by reference.
