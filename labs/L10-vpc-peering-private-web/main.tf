terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      lab        = "L10-vpc-peering-private-web"
      project    = "aws-lab-terraform"
      managed_by = "terraform"
    }
  }
}

# Base only, by design: no peering connection (saa-l10-pcx), no routes in
# either route table beyond the client default, and no inbound rule on the
# host security group. Creating the peering, the two routes, and the port-80
# rule IS the lab.

locals {
  az_host   = "ap-southeast-1a"
  az_client = "ap-southeast-1b"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_prefix_list" "eic" {
  name = "com.amazonaws.${var.aws_region}.ec2-instance-connect.internet"
}

resource "aws_vpc" "host" {
  cidr_block = "10.10.0.0/24"

  tags = {
    Name = "saa-l10-vpc-host"
  }
}

resource "aws_subnet" "host_private" {
  vpc_id            = aws_vpc.host.id
  cidr_block        = "10.10.0.0/28"
  availability_zone = local.az_host

  tags = {
    Name = "saa-l10-sub-private"
  }
}

resource "aws_route_table" "host_private" {
  vpc_id = aws_vpc.host.id

  tags = {
    Name = "saa-l10-rt-private"
  }
}

resource "aws_route_table_association" "host_private" {
  subnet_id      = aws_subnet.host_private.id
  route_table_id = aws_route_table.host_private.id
}

resource "aws_vpc" "client" {
  cidr_block = "10.20.0.0/24"

  tags = {
    Name = "saa-l10-vpc-client"
  }
}

resource "aws_subnet" "client_public" {
  vpc_id                  = aws_vpc.client.id
  cidr_block              = "10.20.0.0/28"
  availability_zone       = local.az_client
  map_public_ip_on_launch = true

  tags = {
    Name = "saa-l10-sub-public"
  }
}

resource "aws_internet_gateway" "client" {
  vpc_id = aws_vpc.client.id

  tags = {
    Name = "saa-l10-igw"
  }
}

resource "aws_route_table" "client_public" {
  vpc_id = aws_vpc.client.id

  tags = {
    Name = "saa-l10-rt-public"
  }
}

resource "aws_route" "client_default" {
  route_table_id         = aws_route_table.client_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.client.id
}

resource "aws_route_table_association" "client_public" {
  subnet_id      = aws_subnet.client_public.id
  route_table_id = aws_route_table.client_public.id
}

# Zero inbound rules. Adding the port-80 rule from the client is the exam point.
resource "aws_security_group" "saa_l10_sg_host" {
  name        = "saa-l10-sg-host"
  description = "Private web host: starts with no inbound rules; the lab adds port 80 from the client."
  vpc_id      = aws_vpc.host.id

  tags = {
    Name = "saa-l10-sg-host"
  }
}

resource "aws_security_group" "saa_l10_sg_client" {
  name        = "saa-l10-sg-client"
  description = "Client: SSH from EC2 Instance Connect only."
  vpc_id      = aws_vpc.client.id

  tags = {
    Name = "saa-l10-sg-client"
  }
}

resource "aws_vpc_security_group_ingress_rule" "client_ssh_eic" {
  security_group_id = aws_security_group.saa_l10_sg_client.id
  description       = "SSH from EC2 Instance Connect"
  prefix_list_id    = data.aws_prefix_list.eic.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_instance" "host" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.host_private.id
  vpc_security_group_ids = [aws_security_group.saa_l10_sg_host.id]

  # Serves HTML on port 80 offline; the script body is copied verbatim from
  # the lab page, so its lines start at column 0.
  user_data = <<-USERDATA
#!/bin/bash
mkdir -p /var/www/html
cat <<'EOF' > /var/www/html/index.html
<h1>Hello from VPC Peering Private Host (ap-southeast-1a)</h1>
EOF
cat <<'EOF' > /etc/systemd/system/simple-web.service
[Unit]
Description=Simple Python HTTP Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server 80 --directory /var/www/html
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now simple-web
  USERDATA

  tags = {
    Name = "saa-l10-ec2-host"
  }
}

resource "aws_instance" "client" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.client_public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.saa_l10_sg_client.id]

  tags = {
    Name = "saa-l10-ec2-client"
  }
}

output "host_vpc_id" {
  description = "Host VPC. Create the peering connection FROM here (or accept here) as the lab directs."
  value       = aws_vpc.host.id
}

output "client_vpc_id" {
  description = "Client VPC, the other side of saa-l10-pcx."
  value       = aws_vpc.client.id
}

output "host_route_table_id" {
  description = "saa-l10-rt-private. You add the route to 10.20.0.0/24 via the peering connection."
  value       = aws_route_table.host_private.id
}

output "client_route_table_id" {
  description = "saa-l10-rt-public. You add the route to 10.10.0.0/24 via the peering connection."
  value       = aws_route_table.client_public.id
}

output "client_instance_public_ip" {
  description = "Client public IP. EC2 Instance Connect into it, then curl the host private IP."
  value       = aws_instance.client.public_ip
}

output "host_instance_id" {
  description = "Private host instance. Read its private IPv4 address for the curl test."
  value       = aws_instance.host.id
}
