# =============================================================================
# Ikimina Tracker: production environment on Azure
#
#   Internet --80--> Bastion VM (public subnet, nginx reverse proxy)
#                       |  SSH (ProxyJump) and HTTP, private network only
#                       v
#                    App VM (private subnet, no public IP, Docker)
#                       |  5432, TLS, private network only
#                       v
#                    Azure Database for PostgreSQL (delegated subnet)
#
#   GitHub Actions --push--> Azure Container Registry --pull--> App VM
#
# Files: network.tf (VNet, subnets, NSGs), compute.tf (bastion + app VMs),
#        database.tf (managed PostgreSQL), registry.tf (ACR),
#        variables.tf (inputs), outputs.tf (IPs, names, IDs).
# =============================================================================

# Short random suffix, so globally unique names (ACR, PostgreSQL) don't clash
# with anyone else's. It is stored in state, so it stays the same on every apply.
resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
