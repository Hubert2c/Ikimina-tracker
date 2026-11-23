output "resource_group_name" {
  description = "Resource group holding all resources."
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "ID of the virtual network."
  value       = module.network.vnet_id
}

output "subnet_id" {
  description = "ID of the application subnet."
  value       = module.network.subnet_id
}

output "nsg_id" {
  description = "ID of the network security group protecting the subnet."
  value       = module.network.nsg_id
}

output "vm_id" {
  description = "ID of the virtual machine."
  value       = module.compute.vm_id
}

output "public_ip" {
  description = "Public IP address of the VM."
  value       = module.compute.public_ip
}

output "private_ip" {
  description = "Private IP address of the VM inside the subnet."
  value       = module.compute.private_ip
}

output "ssh_command" {
  description = "SSH command for the administrator."
  value       = "ssh ${var.admin_username}@${module.compute.public_ip}"
}

output "app_url" {
  description = "Health-check URL of the API once Ansible has deployed it."
  value       = "http://${module.compute.public_ip}:${var.app_port}/health"
}

output "ansible_inventory" {
  description = "Ready-to-paste contents for ansible/inventory/hosts.ini."
  value       = <<-EOT
    [app_servers]
    ${module.compute.vm_name} ansible_host=${module.compute.public_ip} ansible_user=${var.admin_username}
  EOT
}
