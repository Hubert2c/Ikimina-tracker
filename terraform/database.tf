# ========================================== MANAGED POSTGRESQL DATABASE ====
# Azure Database for PostgreSQL Flexible Server with private access (VNet
# integration): it gets a private IP in the delegated subnet and has no public
# endpoint. Azure handles patching, backups (7 days) and TLS.

# Private DNS zone, so the app resolves the server name to its private IP.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.prefix}-${random_string.suffix.result}.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-postgres-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
}

# Generated admin password: never typed, never in Git. It lives only in the
# Terraform state (ignored by Git) and the GitHub DATABASE_URL secret.
# Letters and digits only, so it's safe inside a connection URL without escaping.
resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "azurerm_postgresql_flexible_server" "main" {
  # checkov:skip=CKV2_AZURE_57:Private access uses VNet integration (delegated subnet + private DNS zone, public access disabled), which is the other supported private option; Checkov only recognises private endpoints.
  # checkov:skip=CKV_AZURE_136:Geo-redundant backup doubles backup storage cost; 7-day local backups are enough for this project. See SECURITY.md.
  name                          = "${var.prefix}-db-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = var.postgres_version
  sku_name                      = var.postgres_sku
  storage_mb                    = 32768
  backup_retention_days         = 7
  delegated_subnet_id           = azurerm_subnet.database.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login           = var.postgres_admin_login
  administrator_password        = random_password.postgres.result
  tags                          = var.tags

  # Azure picks an availability zone; don't try to move it on later applies.
  lifecycle {
    ignore_changes = [zone, high_availability]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.postgres_database
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Log every connection and disconnection (an audit trail for the database).
resource "azurerm_postgresql_flexible_server_configuration" "log_connections" {
  name      = "log_connections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "on"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_disconnections" {
  name      = "log_disconnections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "on"
}
