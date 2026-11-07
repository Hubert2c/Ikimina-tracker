output "public_ip" {
  description = "Public IP address of the Ikimina Tracker VM."
  value       = azurerm_public_ip.main.ip_address
}

output "ssh_command" {
  description = "SSH command for the configured administrator."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}
