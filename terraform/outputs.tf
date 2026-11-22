# ------------------------------------------------------------ Public entry ----
output "app_url" {
  description = "Public URL of the live application (nginx on the bastion)."
  value       = "http://${aws_eip.bastion.public_ip}"
}

output "bastion_public_ip" {
  description = "Public (Elastic) IP of the bastion host."
  value       = aws_eip.bastion.public_ip
}

output "ssh_bastion" {
  description = "SSH into the bastion."
  value       = "ssh ${local.admin_username}@${aws_eip.bastion.public_ip}"
}

output "ssh_app" {
  description = "SSH into the private app VM through the bastion."
  value       = "ssh -J ${local.admin_username}@${aws_eip.bastion.public_ip} ${local.admin_username}@${aws_instance.app.private_ip}"
}

# --------------------------------------------------------------- Private ----
output "app_private_ip" {
  description = "Private IP of the app VM (no public IP)."
  value       = aws_instance.app.private_ip
}

output "admin_username" {
  description = "Linux admin user on both VMs."
  value       = local.admin_username
}

# -------------------------------------------------------------- Registry ----
output "ecr_registry" {
  description = "ECR registry host (docker login target)."
  value       = split("/", aws_ecr_repository.app.repository_url)[0]
}

output "ecr_repository_url" {
  description = "Full image name without tag."
  value       = aws_ecr_repository.app.repository_url
}

output "image_repository" {
  description = "ECR repository name."
  value       = aws_ecr_repository.app.name
}

# -------------------------------------------------------------- Database ----
output "postgres_host" {
  description = "Private host name of the RDS PostgreSQL instance."
  value       = aws_db_instance.main.address
}

output "database_url" {
  description = "Connection URL for the app (TLS required). Sensitive: show it with terraform output -raw database_url."
  value       = "postgresql://${var.postgres_admin_login}:${random_password.postgres.result}@${aws_db_instance.main.address}:5432/${var.postgres_database}?sslmode=require"
  sensitive   = true
}

# ------------------------------------------- Values used by the CD pipeline ----
output "aws_region" {
  description = "AWS region of the environment."
  value       = var.region
}

output "aws_account_id" {
  description = "AWS account that holds the environment."
  value       = data.aws_caller_identity.current.account_id
}

output "github_deploy_role_arn" {
  description = "IAM role that GitHub Actions assumes through OIDC."
  value       = aws_iam_role.github_deploy.arn
}

output "bastion_security_group_id" {
  description = "Bastion security group (CD adds a temporary SSH rule for its runner)."
  value       = aws_security_group.bastion.id
}

output "app_port" {
  description = "Port the API container listens on inside the private network."
  value       = var.app_port
}

# ---------------------------------------------------------- Resource IDs ----
output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "bastion_instance_id" {
  description = "ID of the bastion EC2 instance."
  value       = aws_instance.bastion.id
}

output "app_instance_id" {
  description = "ID of the app EC2 instance."
  value       = aws_instance.app.id
}

output "db_instance_id" {
  description = "ID of the RDS instance."
  value       = aws_db_instance.main.identifier
}
