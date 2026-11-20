# ------------------------------------------------------------ Public entry ----
output "app_url" {
  description = "Public URL of the live application (nginx on the bastion)."
  value       = "http://${azurerm_public_ip.bastion.ip_address}"
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = azurerm_public_ip.bastion.ip_address
}

output "ssh_bastion" {
  description = "SSH into the bastion."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.bastion.ip_address}"
}

output "ssh_app" {
  description = "SSH into the private app VM through the bastion."
  value       = "ssh -J ${var.admin_username}@${azurerm_public_ip.bastion.ip_address} ${var.admin_username}@${azurerm_network_interface.app.private_ip_address}"
}

# --------------------------------------------------------------- Private ----
output "app_private_ip" {
  description = "Private IP of the app VM (no public IP)."
  value       = azurerm_network_interface.app.private_ip_address
}

output "admin_username" {
  description = "Linux admin user on both VMs."
  value       = var.admin_username
}

# -------------------------------------------------------------- Registry ----
output "acr_name" {
  description = "Name of the private container registry."
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Login server of the registry (image prefix)."
  value       = azurerm_container_registry.main.login_server
}

# -------------------------------------------------------------- Database ----
output "postgres_fqdn" {
  description = "Private host name of the managed PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "database_url" {
  description = "Connection URL for the app (TLS required). Sensitive: show it with terraform output -raw database_url."
  value       = "postgresql://${var.postgres_admin_login}:${random_password.postgres.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.postgres_database}?sslmode=require"
  sensitive   = true
}

# ------------------------------------------- Names used by the CD pipeline ----
output "resource_group_name" {
  description = "Resource group name."
  value       = azurerm_resource_group.main.name
}

output "public_nsg_name" {
  description = "NSG of the public subnet (CD adds a temporary SSH rule for its runner)."
  value       = azurerm_network_security_group.public.name
}

output "app_port" {
  description = "Port the API container listens on inside the private network."
  value       = var.app_port
}

# ---------------------------------------------------------- Resource IDs ----
output "resource_group_id" {
  description = "ID of the resource group."
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.main.id
}

output "bastion_vm_id" {
  description = "ID of the bastion VM."
  value       = azurerm_linux_virtual_machine.bastion.id
}

output "app_vm_id" {
  description = "ID of the app VM."
  value       = azurerm_linux_virtual_machine.app.id
}

output "postgres_server_id" {
  description = "ID of the PostgreSQL server."
  value       = azurerm_postgresql_flexible_server.main.id
}

output "acr_id" {
  description = "ID of the container registry."
  value       = azurerm_container_registry.main.id
}
