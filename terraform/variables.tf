# ---------------------------------------------------------------- naming ----
variable "project_name" {
  description = "Short project name used in every resource name."
  type        = string
  default     = "ikimina"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.project_name))
    error_message = "project_name must be 2-15 lowercase letters, digits or dashes, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region to deploy into (e.g. southafricanorth). No default: always chosen per environment."
  type        = string
}

variable "tags" {
  description = "Extra tags merged into the default tags on every resource."
  type        = map(string)
  default     = {}
}

# --------------------------------------------------------------- network ----
variable "vnet_address_space" {
  description = "CIDR blocks for the virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]

  validation {
    condition     = alltrue([for c in var.vnet_address_space : can(cidrhost(c, 0))])
    error_message = "Every vnet_address_space entry must be a valid CIDR."
  }
}

variable "subnet_address_prefix" {
  description = "CIDR block for the application subnet (inside vnet_address_space)."
  type        = string
  default     = "10.20.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "subnet_address_prefix must be a valid CIDR."
  }
}

variable "admin_cidr" {
  description = "Single trusted IPv4 CIDR allowed to SSH to the VM (e.g. 198.51.100.10/32)."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0 (SSH open to the internet)."
  }
}

variable "app_port" {
  description = "Public TCP port used by the API container."
  type        = number
  default     = 5000

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535 && var.app_port != 22
    error_message = "app_port must be between 1 and 65535 and must not be 22."
  }
}

variable "app_allowed_cidrs" {
  description = "CIDRs allowed to call the API. Defaults to the whole internet because it is a public API."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.app_allowed_cidrs) > 0 && alltrue([for c in var.app_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "app_allowed_cidrs must contain at least one valid CIDR."
  }
}

# --------------------------------------------------------------- compute ----
variable "vm_size" {
  description = "Azure VM size."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Linux administrator account; password authentication is disabled."
  type        = string
  default     = "ikiminaadmin"

  validation {
    condition     = !contains(["root", "admin", "administrator"], lower(var.admin_username))
    error_message = "admin_username must not be a reserved name such as root or admin."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed for the Linux administrator."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key (ssh-ed25519, ssh-rsa or ecdsa)."
  }
}

variable "os_disk_type" {
  description = "Storage type of the OS disk."
  type        = string
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.os_disk_type)
    error_message = "os_disk_type must be Standard_LRS, StandardSSD_LRS or Premium_LRS."
  }
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB."
  type        = number
  default     = 30
}

variable "encryption_at_host_enabled" {
  description = "Encrypt temp disk and caches on the host. Requires the Microsoft.Compute/EncryptionAtHost feature to be registered on the subscription first."
  type        = bool
  default     = false
}

variable "vm_image" {
  description = "Marketplace image for the VM."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
