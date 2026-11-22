# ========================================== MANAGED POSTGRESQL DATABASE ====
# Amazon RDS for PostgreSQL in the database subnets, with no public endpoint.
# AWS handles patching, backups and encryption at rest; TLS is enforced.

# Generated admin password: never typed, never in Git. It lives only in the
# Terraform state (ignored by Git) and the GitHub DATABASE_URL secret.
# Letters and digits only, so it's safe inside a connection URL without escaping.
resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.prefix}-db-subnets"
  subnet_ids = aws_subnet.database[*].id
  tags       = { Name = "${var.prefix}-db-subnets" }
}

# Server settings: require TLS, and log every connection and disconnection
# (an audit trail for the database).
resource "aws_db_parameter_group" "main" {
  name   = "${var.prefix}-postgres${var.postgres_version}"
  family = "postgres${var.postgres_version}"

  # Static parameter: AWS stores it as pending-reboot. It already matches the
  # PostgreSQL 16 default, so no reboot is needed.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }
}

resource "aws_db_instance" "main" {
  # checkov:skip=CKV_AWS_157:Multi-AZ doubles the database cost; single-AZ with automated backups is enough for this project. See SECURITY.md.
  # checkov:skip=CKV_AWS_118:Enhanced monitoring is a paid add-on.
  # checkov:skip=CKV_AWS_353:Performance Insights is not needed at this scale.
  # checkov:skip=CKV_AWS_161:The app authenticates with a generated password over TLS; IAM database auth would need AWS credentials on the VM.
  # checkov:skip=CKV_AWS_293:Deletion protection is off so `terraform destroy` can clean up the student environment and stop costs.
  # checkov:skip=CKV2_AWS_30:Query logging is off to keep log volume (and cost) low; connections and disconnections are logged.
  identifier     = "${var.prefix}-db"
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.postgres_database
  username = var.postgres_admin_login
  password = random_password.postgres.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period         = var.db_backup_retention_days
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = true

  # Student environment: allow a clean `terraform destroy`.
  deletion_protection = false
  skip_final_snapshot = true

  tags = { Name = "${var.prefix}-db" }
}
