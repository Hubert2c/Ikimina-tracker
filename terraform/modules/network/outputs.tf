output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "subnet_id" {
  description = "ID of the application subnet."
  value       = azurerm_subnet.app.id
}

output "nsg_id" {
  description = "ID of the application network security group."
  value       = azurerm_network_security_group.app.id
}
