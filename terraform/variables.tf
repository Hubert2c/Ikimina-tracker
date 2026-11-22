# ------------------------------------------------- Environment specifics ----
variable "region" {
  description = "AWS region for every resource, e.g. eu-west-1. af-south-1 (Cape Town) must be enabled in your account first."
  type        = string
}

variable "prefix" {
  description = "Short name prefix for all resources (lowercase letters, digits, dashes)."
  type        = string
  default     = "ikimina"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.prefix))
    error_message = "prefix must be 2-15 lowercase letters, digits or dashes, starting with a letter."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    application = "ikimina-tracker"
    environment = "production"
    managed_by  = "terraform"
  }
}

# -------------------------------------------------------------- Network ----
variable "vpc_cidr" {
  description = "Address range of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet (bastion host)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet (app VM, no public IP)."
  type        = string
  default     = "10.20.2.0/24"
}

variable "database_subnet_cidrs" {
  description = "Two database subnets in different availability zones (RDS requires two)."
  type        = list(string)
  default     = ["10.20.3.0/24", "10.20.4.0/24"]

  validation {
    condition     = length(var.database_subnet_cidrs) == 2
    error_message = "database_subnet_cidrs must contain exactly two CIDR ranges."
  }
}

variable "app_private_ip" {
  description = "Fixed private IP of the app VM (must be inside private_subnet_cidr; AWS reserves .0 to .3 and the last address)."
  type        = string
  default     = "10.20.2.10"
}

variable "admin_cidr" {
  description = "The only IPv4 range allowed to SSH to the bastion, e.g. your IP as 198.51.100.10/32."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "app_port" {
  description = "TCP port the API container listens on (the app VM only; the public uses port 80 on the bastion)."
  type        = number
  default     = 5000

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
}

# -------------------------------------------------------------- Compute ----
variable "ssh_public_key" {
  description = "OpenSSH public key installed on both VMs (user: ubuntu)."
  type        = string
}

variable "bastion_instance_type" {
  description = "EC2 instance type of the bastion (SSH, nginx and NAT only)."
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "EC2 instance type of the app VM."
  type        = string
  default     = "t3.micro"
}

# ------------------------------------------------------------- Database ----
variable "postgres_version" {
  description = "PostgreSQL major version (also selects the parameter group family)."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "RDS instance class (db.t4g.micro and db.t3.micro are free-tier eligible)."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_backup_retention_days" {
  description = "Days of automated RDS backups. Free-tier accounts may be limited to 1; raise to 7 on a paid account."
  type        = number
  default     = 1

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35
    error_message = "db_backup_retention_days must be between 1 and 35."
  }
}

variable "postgres_admin_login" {
  description = "Administrator user name for PostgreSQL."
  type        = string
  default     = "ikiminaadmin"
}

variable "postgres_database" {
  description = "Name of the application database."
  type        = string
  default     = "ikimina"
}

# ------------------------------------------------------------- Registry ----
variable "image_repository" {
  description = "Name of the ECR repository for the app image."
  type        = string
  default     = "ikimina-tracker"
}

# ------------------------------------------------------ GitHub Actions CD ----
variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to deploy through OIDC."
  type        = string
  default     = "Hubert2c/Ikimina-tracker"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider in this AWS account. Set false if the account already has one."
  type        = bool
  default     = true
}
