# ------------------------------------------------- Environment specifics ----
variable "location" {
  description = "Azure region for every resource, e.g. southafricanorth. Azure for Students only allows some regions."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group that holds everything."
  type        = string
  default     = "ikimina-rg"
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
variable "vnet_cidr" {
  description = "Address space of the virtual network."
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

variable "database_subnet_cidr" {
  description = "Subnet delegated to Azure Database for PostgreSQL."
  type        = string
  default     = "10.20.3.0/24"
}

variable "app_private_ip" {
  description = "Fixed private IP of the app VM (must be inside private_subnet_cidr; Azure reserves .0 to .3)."
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
variable "admin_username" {
  description = "Linux admin account on both VMs (SSH keys only, passwords disabled)."
  type        = string
  default     = "ikiminaadmin"
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed on both VMs."
  type        = string
}

variable "bastion_vm_size" {
  description = "Size of the bastion VM (it only runs SSH and nginx)."
  type        = string
  default     = "Standard_B1s"
}

variable "app_vm_size" {
  description = "Size of the app VM."
  type        = string
  default     = "Standard_B1s"
}

# ------------------------------------------------------------- Database ----
variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "postgres_sku" {
  description = "Azure Database for PostgreSQL SKU (B_ = Burstable, cheapest)."
  type        = string
  default     = "B_Standard_B1ms"
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
variable "acr_sku" {
  description = "Azure Container Registry SKU."
  type        = string
  default     = "Basic"
}
