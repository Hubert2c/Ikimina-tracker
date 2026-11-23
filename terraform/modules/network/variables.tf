variable "name_prefix" {
  description = "Prefix for every resource name in this module (e.g. ikimina-dev)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the network resources."
  type        = string
}

variable "location" {
  description = "Azure region for the network resources."
  type        = string
}

variable "vnet_address_space" {
  description = "CIDR blocks for the virtual network."
  type        = list(string)
}

variable "subnet_address_prefix" {
  description = "CIDR block for the application subnet (must sit inside vnet_address_space)."
  type        = string
}

variable "admin_cidr" {
  description = "Single trusted CIDR allowed to reach SSH (port 22)."
  type        = string
}

variable "app_port" {
  description = "TCP port the API listens on."
  type        = number
}

variable "app_allowed_cidrs" {
  description = "CIDRs allowed to reach the API port."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
