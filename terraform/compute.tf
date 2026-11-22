# Latest Ubuntu 24.04 LTS image published by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.prefix}-admin"
  public_key = var.ssh_public_key
}

# ================================================================ BASTION ====
# Small VM in the public subnet. Three jobs:
#   1. Jump host: the only way to SSH (and run Ansible) into the private VM.
#   2. Reverse proxy: nginx on port 80 forwards public traffic to the app VM.
#   3. NAT: forwards the private subnet's outbound traffic to the internet.
resource "aws_instance" "bastion" {
  # checkov:skip=CKV_AWS_126:Detailed (1-minute) monitoring is a paid add-on; basic 5-minute metrics are enough here.
  # checkov:skip=CKV2_AWS_41:No IAM role on purpose: the VM never calls AWS APIs, so it holds no AWS credentials at all.
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = false # the Elastic IP below is the public address
  source_dest_check           = false # required for NAT: it forwards other hosts' packets
  ebs_optimized               = true

  user_data = templatefile("${path.module}/templates/bastion-nat.sh.tftpl", {
    private_subnet_cidr = var.private_subnet_cidr
  })

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 10
    encrypted   = true
  }

  tags = { Name = "${var.prefix}-bastion", role = "bastion" }

  lifecycle {
    # ami: don't replace the VM every time Canonical publishes a new image.
    # associate_public_ip_address: once the Elastic IP is attached, AWS reports
    # true here, which would otherwise force a replacement on every apply.
    ignore_changes = [ami, associate_public_ip_address]
  }
}

# Static public IP, so the URL and SSH address survive a stop/start.
resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id
  tags     = { Name = "${var.prefix}-bastion-ip" }

  depends_on = [aws_internet_gateway.main]
}

# ================================================================= APP VM ====
# Runs the Docker container. Private IP only: unreachable from the internet.
resource "aws_instance" "app" {
  # checkov:skip=CKV_AWS_126:Detailed (1-minute) monitoring is a paid add-on; basic 5-minute metrics are enough here.
  # checkov:skip=CKV2_AWS_41:No IAM role on purpose: the deploy pipeline hands the VM a short-lived ECR token, so it holds no AWS credentials.
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.app_instance_type
  subnet_id                   = aws_subnet.private.id
  private_ip                  = var.app_private_ip
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = false
  ebs_optimized               = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = { Name = "${var.prefix}-app", role = "app" }

  lifecycle {
    ignore_changes = [ami]
  }

  # Outbound internet (through the bastion NAT) must exist before Ansible runs.
  depends_on = [aws_route_table_association.private]
}
