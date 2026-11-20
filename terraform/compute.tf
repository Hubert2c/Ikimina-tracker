# ================================================================ BASTION ====
# Small VM in the public subnet. Two jobs:
#   1. Jump host: the only way to SSH (and run Ansible) into the private VM.
#   2. Reverse proxy: nginx on port 80 forwards public traffic to the app VM.
resource "azurerm_public_ip" "bastion" {
  name                = "${var.prefix}-bastion-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "bastion" {
  # checkov:skip=CKV_AZURE_119:The bastion is the single public entry point by design (jump host + reverse proxy). Its NSG allows only SSH from admin_cidr and HTTP; see SECURITY.md.
  name                = "${var.prefix}-bastion-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bastion.id
  }
}

resource "azurerm_linux_virtual_machine" "bastion" {
  name                            = "${var.prefix}-bastion"
  computer_name                   = "${var.prefix}-bastion"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = var.bastion_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  allow_extension_operations      = false # no VM extensions (Checkov CKV_AZURE_50); Ansible configures the host over SSH
  network_interface_ids           = [azurerm_network_interface.bastion.id]
  tags                            = merge(var.tags, { role = "bastion" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# ================================================================= APP VM ====
# Runs the Docker container. Private IP only: unreachable from the internet.
resource "azurerm_network_interface" "app" {
  name                = "${var.prefix}-app-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.app_private_ip
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  name                            = "${var.prefix}-app"
  computer_name                   = "${var.prefix}-app"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = var.app_vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  allow_extension_operations      = false
  network_interface_ids           = [azurerm_network_interface.app.id]
  tags                            = merge(var.tags, { role = "app" })

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
