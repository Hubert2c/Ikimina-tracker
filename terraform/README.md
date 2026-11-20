# Terraform: Azure infrastructure for Ikimina Tracker

This folder provisions everything the app needs to run on Azure. Ansible then
configures the server (see [../ansible/README.md](../ansible/README.md)).

## What gets created

| Resource | Terraform name | Purpose |
|----------|----------------|---------|
| Resource group | `azurerm_resource_group.main` | Holds every resource, so `terraform destroy` removes them all |
| Virtual network `10.20.0.0/16` | `azurerm_virtual_network.main` | Private network for the VM |
| Subnet `10.20.1.0/24` | `azurerm_subnet.main` | Where the VM's network card lives |
| Network security group | `azurerm_network_security_group.main` | Firewall: SSH (22) **only from `admin_cidr`**, API port open; all other inbound traffic denied |
| NSG associations | `azurerm_subnet_network_security_group_association.main`, `azurerm_network_interface_security_group_association.main` | Applies the NSG to both the subnet and the NIC |
| Static public IP | `azurerm_public_ip.main` | Stable address for SSH and the API |
| Network interface | `azurerm_network_interface.main` | Connects the VM to the subnet and the public IP |
| Ubuntu 24.04 VM (`Standard_B2s`) | `azurerm_linux_virtual_machine.main` | Runs Docker and the app; SSH key login only, password login and VM extensions disabled |

## Files

| File | Contents |
|------|----------|
| `versions.tf` | Required Terraform (>= 1.6) and `azurerm` provider (~> 4.0) versions |
| `variables.tf` | All environment-specific inputs. Nothing about the region, IPs or keys is hardcoded |
| `main.tf` | The resources above |
| `outputs.tf` | IPs, resource IDs and ready-to-use SSH and URL strings |
| `terraform.tfvars.example` | Template for your own `terraform.tfvars` (which Git ignores) |
| `.terraform.lock.hcl` | Locks the exact provider version, so everyone gets the same build |

## Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `location` | **yes** | none | Azure region, e.g. `southafricanorth` |
| `ssh_public_key` | **yes** | none | Your OpenSSH public key (`cat ~/.ssh/id_ed25519.pub`) |
| `admin_cidr` | **yes** | none | The only IP range allowed to SSH, e.g. your IP as `/32` |
| `resource_group_name` | no | `ikimina-rg` | Resource group name |
| `vm_name` | no | `ikimina-vm` | Prefix for the VM and its resources |
| `vm_size` | no | `Standard_B2s` | Azure VM size |
| `admin_username` | no | `ikiminaadmin` | Linux admin user |
| `app_port` | no | `5000` | Public API port (validated to be 1 to 65535) |
| `tags` | no | app and managed-by tags | Tags on every resource |

There are no secrets in this configuration. Authentication uses your Azure CLI
login, and the VM uses SSH keys, not passwords.

## Outputs

| Output | Example use |
|--------|-------------|
| `public_ip` | Put into the Ansible inventory |
| `private_ip` | Address inside the VNet |
| `ssh_command` | Copy and paste to log in |
| `api_url` | Health check URL after deployment |
| `resource_group_id`, `vnet_id`, `subnet_id`, `nsg_id`, `vm_id` | Azure resource IDs for the portal, CLI or other tooling |

Show them any time with `terraform output` (or `terraform output -raw public_ip`).

## How to use it

### 1. Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/install) 1.6 or newer
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and an Azure subscription
- An SSH key pair (`ssh-keygen -t ed25519` if you don't have one)

### 2. Sign in to Azure
```bash
az login
az account set --subscription "<subscription name or id>"
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

### 3. Set your values
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: location, admin_cidr (curl ifconfig.me, then add /32), ssh_public_key
```

### 4. Initialise, plan, apply
```bash
terraform init      # downloads the azurerm provider (version from .terraform.lock.hcl)
terraform fmt -check
terraform validate  # syntax and type check, no Azure calls
terraform plan      # shows exactly what will be created. Review it
terraform apply     # type "yes" to create the resources (this costs money)
terraform output    # IPs and IDs for the next step
```

Next, configure the server with Ansible: [../ansible/README.md](../ansible/README.md).

### 5. Tear down
```bash
terraform destroy   # deletes the whole resource group to stop charges
```

## Quality and security checks in CI

Every pull request runs:
- **Infrastructure validation:** `terraform fmt -check` and `terraform validate`
- **Security scan (IaC):** Checkov. Two findings were fixed and one is an
  accepted risk with a documented skip comment in `main.tf`. See
  [../SECURITY.md](../SECURITY.md).

State files (`*.tfstate`), `.terraform/` and `*.tfvars` are ignored by Git, so
real IPs and keys are never committed.
