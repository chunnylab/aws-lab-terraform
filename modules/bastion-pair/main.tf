# Deliberate omissions, by design:
# - No NAT gateway and no default route in the private route table. L11 Stage 1
#   teaches by watching `aws s3 ls` time out from the private subnet.
# - No user data on either instance. The labs that need a service install it in
#   their own root modules or the learner does it as part of the lesson.

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ec2_managed_prefix_list" "eic" {
  count = var.enable_eic_prefix ? 1 : 0

  name = "com.amazonaws.${var.aws_region}.ec2-instance-connect"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = var.az

  tags = {
    Name = "${var.name_prefix}-sub-public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = var.az

  tags = {
    Name = "${var.name_prefix}-sub-private"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-rt-public"
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Local routes only. The learner adds the real paths as part of the lesson.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-rt-private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_key_pair" "this" {
  key_name   = "${var.name_prefix}-key"
  public_key = var.public_key

  tags = {
    Name = "${var.name_prefix}-key"
  }
}

resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-sg-bastion"
  description = "Bastion: SSH from admin CIDR${var.enable_eic_prefix ? " and EC2 Instance Connect" : ""}."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-sg-bastion"
  }
}

resource "aws_security_group" "private" {
  name        = "${var.name_prefix}-sg-private"
  description = "Private host: SSH from the bastion security group only."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-sg-private"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_admin" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from admin CIDR"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_eic" {
  count = var.enable_eic_prefix ? 1 : 0

  security_group_id = aws_security_group.bastion.id
  description       = "SSH from EC2 Instance Connect"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.eic[0].id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "private_from_bastion" {
  security_group_id            = aws_security_group.private.id
  description                  = "SSH from the bastion security group"
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

# Terraform drops the AWS default allow-all egress when a security group
# declares none, so outbound rules are explicit here. The bastion's whole job
# is jumping to the private host.
resource "aws_vpc_security_group_egress_rule" "bastion_ssh_private" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "SSH to the private host"
  referenced_security_group_id = aws_security_group.private.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

# HTTPS out for the endpoint lessons. The Stage 1 timeout still happens: the
# private route table has no route to carry these packets until the lab adds
# one. DNS out covers private-DNS resolution for the Interface endpoint.
resource "aws_vpc_security_group_egress_rule" "private_https" {
  security_group_id = aws_security_group.private.id
  description       = "HTTPS outbound (Gateway/Interface endpoint traffic)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "private_dns_tcp" {
  security_group_id = aws_security_group.private.id
  description       = "DNS to the VPC resolver"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "private_dns_udp" {
  security_group_id = aws_security_group.private.id
  description       = "DNS to the VPC resolver"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_iam_role" "private_readonly" {
  count = var.create_iam_role ? 1 : 0

  name = "${var.name_prefix}-role-private"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-role-private"
  }
}

resource "aws_iam_role_policy_attachment" "private_readonly" {
  for_each = var.create_iam_role ? toset([
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess",
  ]) : toset([])

  role       = aws_iam_role.private_readonly[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "private_readonly" {
  count = var.create_iam_role ? 1 : 0

  name = "${var.name_prefix}-role-private"
  role = aws_iam_role.private_readonly[0].name
}

resource "aws_instance" "bastion" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]

  tags = {
    Name = "${var.name_prefix}-ec2-bastion"
  }
}

resource "aws_instance" "private" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.private.id]

  iam_instance_profile = var.create_iam_role ? aws_iam_instance_profile.private_readonly[0].name : null

  tags = {
    Name = "${var.name_prefix}-ec2-private"
  }
}
