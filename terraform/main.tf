# =============================================================================
# Ikimina Tracker: production environment on AWS
#
#   Internet --80--> Bastion EC2 (public subnet, nginx reverse proxy + NAT)
#                       |  SSH (ProxyJump) and HTTP, private network only
#                       v
#                    App EC2 (private subnet, no public IP, Docker)
#                       |  5432, TLS, private network only
#                       v
#                    Amazon RDS for PostgreSQL (database subnets, 2 AZs)
#
#   GitHub Actions --push--> Amazon ECR --pull--> App EC2
#
# Outbound internet for the private subnet (apt, Docker, ECR pulls) goes
# through the bastion, which also acts as a small NAT instance. A managed NAT
# gateway would cost about USD 32/month; see SECURITY.md (accepted risks).
#
# Files: network.tf (VPC, subnets, routes, security groups), compute.tf
#        (bastion + app EC2), database.tf (RDS PostgreSQL), registry.tf (ECR),
#        github_oidc.tf (deploy role for GitHub Actions), variables.tf
#        (inputs), outputs.tf (IPs, names, IDs).
# =============================================================================

data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394:Only the first two zones are used. If AWS ever changes that list, terraform plan shows the subnet move for review before anything is applied.
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  # The app VM and bastion share one AZ; RDS needs subnets in two.
  primary_az   = data.aws_availability_zones.available.names[0]
  secondary_az = data.aws_availability_zones.available.names[1]

  # Ubuntu AMIs on AWS create this user and install the key pair for it.
  admin_username = "ubuntu"
}
