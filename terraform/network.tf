# ------------------------------------------------------------------- VPC ----
resource "aws_vpc" "main" {
  # checkov:skip=CKV2_AWS_11:VPC flow logs add CloudWatch cost; security groups and host firewalls are the controls here. See SECURITY.md.
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.prefix}-vpc" }
}

# Lock down the VPC's default security group (nothing uses it).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-default-sg-unused" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-igw" }
}

# --------------------------------------------------------------- Subnets ----
# Public subnet: only the bastion host lives here. Instances get no automatic
# public IP; the bastion uses an Elastic IP instead.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.primary_az
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.prefix}-public-subnet" }
}

# Private subnet: the app VM has no public IP. Outbound traffic goes through
# the bastion's NAT (see the private route table below).
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.primary_az
  tags              = { Name = "${var.prefix}-private-subnet" }
}

# Database subnets: RDS requires a subnet group spanning two AZs. They have
# no route to the internet at all.
resource "aws_subnet" "database" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = count.index == 0 ? local.primary_az : local.secondary_az
  tags              = { Name = "${var.prefix}-db-subnet-${count.index + 1}" }
}

# ---------------------------------------------------------- Route tables ----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-public-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private subnet: default route through the bastion's network interface,
# which forwards and masquerades the traffic (NAT instance).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-private-rt" }

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.bastion.primary_network_interface_id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Database subnets: local VPC traffic only (no internet route).
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.prefix}-db-rt" }
}

resource "aws_route_table_association" "database" {
  count          = 2
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ------------------------------------------------- Security group: bastion ----
resource "aws_security_group" "bastion" {
  name        = "${var.prefix}-bastion-sg"
  description = "Bastion: SSH from the admin IP, public HTTP, NAT for the private subnet"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.prefix}-bastion-sg" }
}

# SSH to the bastion only from the administrator's IP. The CD pipeline adds a
# temporary rule for its runner's IP during a deploy and removes it after.
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_admin" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from the administrator"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.admin_cidr
}

# Public web traffic to the nginx reverse proxy on the bastion.
resource "aws_vpc_security_group_ingress_rule" "bastion_http" {
  # checkov:skip=CKV_AWS_260:Port 80 is the public web entry point by design (nginx reverse proxy). No domain or certificate yet, so TLS is a documented accepted risk; see SECURITY.md.
  security_group_id = aws_security_group.bastion.id
  description       = "Public HTTP to the nginx reverse proxy"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Traffic from the private subnet that the bastion forwards to the internet.
resource "aws_vpc_security_group_ingress_rule" "bastion_nat" {
  security_group_id = aws_security_group.bastion.id
  description       = "Outbound traffic from the private subnet (NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = var.private_subnet_cidr
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  # checkov:skip=CKV_AWS_382:The bastion is the NAT for the private subnet, so it must reach any internet address (apt mirrors, Docker Hub, ECR).
  security_group_id = aws_security_group.bastion.id
  description       = "All outbound (internet access and NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------- Security group: app ----
resource "aws_security_group" "app" {
  name        = "${var.prefix}-app-sg"
  description = "App VM: SSH and the API port from the bastion only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.prefix}-app-sg" }
}

# SSH only from the bastion (Ansible and admins jump through it).
resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  # checkov:skip=CKV_AWS_24:False positive: the source is the bastion's security group (referenced_security_group_id), not 0.0.0.0/0.
  security_group_id            = aws_security_group.app.id
  description                  = "SSH from the bastion"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

# The API port only from the bastion (nginx forwards public traffic here).
resource "aws_vpc_security_group_ingress_rule" "app_api" {
  security_group_id            = aws_security_group.app.id
  description                  = "API port from the bastion's nginx"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  # checkov:skip=CKV_AWS_382:The app VM pulls packages and images from the internet (through the bastion NAT) and connects to RDS.
  security_group_id = aws_security_group.app.id
  description       = "All outbound (packages, images, database)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ----------------------------------------------- Security group: database ----
# PostgreSQL only from the app VM. No egress rules: the database never
# initiates connections.
resource "aws_security_group" "database" {
  name        = "${var.prefix}-db-sg"
  description = "RDS PostgreSQL: port 5432 from the app VM only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.prefix}-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "database_postgres" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the app VM"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}
