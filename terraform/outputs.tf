output "public_ip" {
  description = "Public IP address of the Ikimina Tracker VM."
  value       = azurerm_public_ip.main.ip_address
}

output "private_ip" {
  description = "Private IP address of the VM inside the virtual network."
  value       = azurerm_network_interface.main.private_ip_address
}

output "ssh_command" {
  description = "SSH command for the configured administrator."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}

output "api_url" {
  description = "URL of the API health endpoint once Ansible has deployed the app."
  value       = "http://${azurerm_public_ip.main.ip_address}:${var.app_port}/health"
}

output "resource_group_id" {
  description = "ID of the resource group that holds every resource."
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "ID of the subnet the VM is attached to."
  value       = azurerm_subnet.main.id
}

output "nsg_id" {
  description = "ID of the network security group."
  value       = azurerm_network_security_group.main.id
}

output "vm_id" {
  description = "ID of the Linux virtual machine."
  value       = azurerm_linux_virtual_machine.main.id
}
