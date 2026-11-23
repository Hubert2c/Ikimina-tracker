# Root module: one resource group, then the network and compute modules.
# Every name is derived from project_name + environment, so the same code can
# create separate dev / staging / prod copies from different .tfvars files.

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    {
      application = "ikimina-tracker"
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags,
  )
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "./modules/network"

  name_prefix           = local.name_prefix
  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  vnet_address_space    = var.vnet_address_space
  subnet_address_prefix = var.subnet_address_prefix
  admin_cidr            = var.admin_cidr
  app_port              = var.app_port
  app_allowed_cidrs     = var.app_allowed_cidrs
  tags                  = local.tags
}

module "compute" {
  source = "./modules/compute"

  name_prefix                = local.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  subnet_id                  = module.network.subnet_id
  vm_size                    = var.vm_size
  admin_username             = var.admin_username
  ssh_public_key             = var.ssh_public_key
  os_disk_type               = var.os_disk_type
  os_disk_size_gb            = var.os_disk_size_gb
  encryption_at_host_enabled = var.encryption_at_host_enabled
  image                      = var.vm_image
  tags                       = local.tags
}
