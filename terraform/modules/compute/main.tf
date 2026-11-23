# Compute layer: a static public IP, a network interface in the app subnet,
# and the Ubuntu VM that Ansible later configures.

resource "azurerm_public_ip" "this" {
  name                = "${var.name_prefix}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard" # Standard SKU is closed by default; only the NSG opens it
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  # checkov:skip=CKV_AZURE_119:Single-VM design with no load balancer or bastion; the public IP is how users and Ansible reach the VM. Exposure is limited by the subnet NSG. See SECURITY.md (accepted risks).
  name                = "${var.name_prefix}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                  = "${var.name_prefix}-vm"
  computer_name         = "${var.name_prefix}-vm"
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  network_interface_ids = [azurerm_network_interface.this.id]
  tags                  = var.tags

  # Key-only login. Password authentication is switched off entirely.
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  # VM extensions can run arbitrary scripts as root; Ansible over SSH is the
  # only configuration path, so extensions are disabled.
  allow_extension_operations = false
  encryption_at_host_enabled = var.encryption_at_host_enabled

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  # Serial console / boot screenshots, stored in an Azure-managed account.
  boot_diagnostics {}
}
