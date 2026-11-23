# Terraform: Azure infrastructure for Ikimina Tracker

This directory provisions everything the API needs on Azure. Ansible then
configures the server (see [../ansible/README.md](../ansible/README.md)).

```text
terraform/
├── versions.tf              # Terraform + azurerm provider versions
├── variables.tf             # every input, with types, defaults and validation
├── main.tf                  # resource group + calls the two modules
├── outputs.tf               # IPs, resource IDs, SSH command, Ansible inventory
├── terraform.tfvars.example # copy to terraform.tfvars (git-ignored)
└── modules/
    ├── network/             # VNet, subnet, NSG (+ subnet association)
    └── compute/             # public IP, NIC, Ubuntu 24.04 VM
```

## What gets created

| Resource | Module | Purpose |
|----------|--------|---------|
| Resource group `<project>-<env>-rg` | root | Holds everything; deleting it removes the whole environment |
| Virtual network (`vnet_address_space`, default `10.20.0.0/16`) | network | Private network for the app |
| Subnet (`subnet_address_prefix`, default `10.20.1.0/24`) | network | Where the VM's NIC lives |
| Network security group | network | Cloud firewall: SSH from `admin_cidr` only, API port from `app_allowed_cidrs`, explicit deny-all for everything else |
| NSG ↔ subnet association | network | Applies the NSG to every VM in the subnet |
| Static Standard public IP | compute | Fixed address for the API and for Ansible |
| Network interface | compute | Connects the VM to the subnet and public IP |
| Linux VM (Ubuntu 24.04, `Standard_B2s`) | compute | Runs Docker + the app. SSH-key login only, VM extensions disabled |

```text
Internet ──► Public IP ──► NSG (22 from admin_cidr / app_port / deny rest)
                              │
               VNet 10.20.0.0/16 └─ Subnet 10.20.1.0/24 ─ NIC ─ VM (Docker: app + PostgreSQL)
```

## Design choices

- **Modules:** `network` and `compute` are separate, reusable modules. The root
  module only wires them together, passing `module.network.subnet_id` into
  `compute`.
- **No hard-coded environment values:** region, CIDRs, ports, VM size, disk,
  image and admin user are all variables. Names come from
  `project_name` + `environment`, so `dev`, `staging` and `prod` can sit side by
  side using different `.tfvars` files.
- **Input validation:** invalid values fail at `terraform plan`, before
  anything is created. Examples: `admin_cidr = "0.0.0.0/0"` (SSH open to the
  world), an invalid CIDR, a port outside 1-65535, `root` as the admin user,
  or something that is not an SSH public key.
- **No secrets in code:** Azure credentials come from `az login`. The SSH
  *public* key is supplied through `terraform.tfvars`, which is git-ignored.
  State files are git-ignored too.
- **Tags:** every resource gets `application`, `environment` and `managed_by`
  tags. The Ansible dynamic inventory uses these tags to find the VM.

## Prerequisites

- Terraform >= 1.6 (`terraform -version`)
- Azure CLI (`az version`) and an Azure subscription
- An SSH key pair, for example `ssh-keygen -t ed25519`

## Initialize and apply

```bash
cd terraform

# 1. Sign in and choose the subscription (azurerm v4 requires it)
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
#   PowerShell: $env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv

# 2. Provide your values
cp terraform.tfvars.example terraform.tfvars
#    edit: environment, location, admin_cidr (your IP/32), ssh_public_key

# 3. Download the provider (versions locked in .terraform.lock.hcl)
terraform init

# 4. Check formatting and validity
terraform fmt -check -recursive
terraform validate

# 5. Preview the changes, then apply exactly that plan
terraform plan -out=tfplan
terraform apply tfplan
```

When it finishes, Terraform prints the outputs:

| Output | Example / use |
|--------|---------------|
| `public_ip` | `20.87.x.x`: Ansible's `ansible_host` |
| `private_ip` | `10.20.1.4` |
| `vm_id`, `vnet_id`, `subnet_id`, `nsg_id`, `resource_group_name` | Azure resource IDs |
| `ssh_command` | `ssh ikiminaadmin@20.87.x.x` |
| `app_url` | `http://20.87.x.x:5000/health` (works after Ansible runs) |
| `ansible_inventory` | Paste into `ansible/inventory/hosts.ini` |

```bash
terraform output -raw ansible_inventory > ../ansible/inventory/hosts.ini
```

## Several environments

```bash
terraform workspace new prod
terraform apply -var-file=prod.tfvars   # environment = "prod", different region/CIDRs
```

## Tear down

```bash
terraform destroy
```

## CI checks on this directory

Every push and pull request runs `terraform fmt -check`, `terraform init
-backend=false` and `terraform validate` ("Infrastructure validation" job), and
Checkov scans it for misconfigurations ("Security scan (IaC)" job). See
[../SECURITY.md](../SECURITY.md).
