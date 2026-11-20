# ============================================ PRIVATE CONTAINER REGISTRY ====
# Azure Container Registry. The CD pipeline pushes each image here (tagged
# with the Git commit SHA), and the app VM pulls it. The admin user is
# disabled: access uses Microsoft Entra ID identities only, and the VM pulls
# with a short-lived token.
resource "azurerm_container_registry" "main" {
  # Premium-only features are skipped (cost). See SECURITY.md, accepted risks.
  # checkov:skip=CKV_AZURE_139:Disabling public network access requires the Premium SKU (about 10x the Basic price)
  # checkov:skip=CKV_AZURE_165:Geo-replication requires the Premium SKU
  # checkov:skip=CKV_AZURE_166:Image quarantine requires the Premium SKU
  # checkov:skip=CKV_AZURE_167:Untagged-manifest retention policy requires the Premium SKU
  # checkov:skip=CKV_AZURE_233:Zone redundancy requires the Premium SKU
  # checkov:skip=CKV_AZURE_237:Dedicated data endpoints require the Premium SKU
  # checkov:skip=CKV_AZURE_164:Content trust (signed images) requires the Premium SKU
  # checkov:skip=CKV_AZURE_163:Images are already scanned with Trivy in CI before they are pushed
  name                = "${replace(var.prefix, "-", "")}acr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}
