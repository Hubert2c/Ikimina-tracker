variable "location" {
  description = "Azure region in which to create the VM and its network."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group."
  type        = string
  default     = "ikimina-rg"
}

variable "vm_name" {
  description = "Name used for the Linux virtual machine and related resources."
  type        = string
  default     = "ikimina-vm"
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Linux administrator account; password authentication is disabled."
  type        = string
  default     = "ikiminaadmin"
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed for the Linux administrator."
  type        = string
}

variable "admin_cidr" {
  description = "Single trusted IPv4 CIDR allowed to SSH to the VM (for example 198.51.100.10/32)."
  type        = string
}

variable "app_port" {
  description = "Public TCP port used by the API container."
  type        = number
  default     = 5000

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
}

variable "tags" {
  description = "Tags applied to Azure resources."
  type        = map(string)
  default = {
    application = "ikimina-tracker"
    managed_by  = "terraform"
  }
}
