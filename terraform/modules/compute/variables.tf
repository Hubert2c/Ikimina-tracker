variable "name_prefix" {
  description = "Prefix for every resource name in this module (e.g. ikimina-dev)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the compute resources."
  type        = string
}

variable "location" {
  description = "Azure region for the compute resources."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the VM's network interface is placed in."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size."
  type        = string
}

variable "admin_username" {
  description = "Linux administrator account (SSH key login only)."
  type        = string
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed for the administrator."
  type        = string
}

variable "os_disk_type" {
  description = "Storage type of the OS disk."
  type        = string
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB."
  type        = number
}

variable "encryption_at_host_enabled" {
  description = "Encrypt temp disk and caches on the host (needs the EncryptionAtHost feature registered on the subscription)."
  type        = bool
}

variable "image" {
  description = "Marketplace image used for the VM."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
