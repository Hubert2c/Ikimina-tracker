# Ansible: configure the VMs and deploy the app

`playbook.yml` takes the two bare Ubuntu VMs that Terraform created and turns
them into a working, hardened production system. The CD pipeline runs it on
every merge to `main`, and you can also run it by hand.

## What it does

### Play 1: `bastion` (public subnet)
| Task | Details |
|------|---------|
| Packages | nginx, UFW, fail2ban |
| SSH hardening | keys only, no root login, `MaxAuthTries 3`, `AllowUsers` admin, `AllowTcpForwarding local` (needed for ProxyJump), validated with `sshd -t` |
| **Reverse proxy** | nginx on port 80 forwards to `10.20.2.10:5000` (the app VM); `server_tokens off`, 16 KB body limit, `/nginx-health` |
| Firewall | UFW deny-all inbound, allow 22 and 80 (the AWS security group further limits 22 to the admin IP and the CD runner) |
| **NAT forwarding** | UFW route rule allowing traffic from the app subnet (`app_subnet_cidr`) to be forwarded; the NAT itself is set up at boot by Terraform |

### Play 2: `app_servers` (private subnet, reached through the bastion)
| Task | Details |
|------|---------|
| Check inputs | fails early if the registry, token, image tag or database URL are missing |
| **Install Docker and Docker Compose** | `docker.io`, `docker-compose-v2`, plus UFW and fail2ban |
| SSH hardening | same as above, but with `AllowTcpForwarding no` |
| Firewall | UFW deny-all inbound, allow 22 and 5000 **from the bastion subnet only** |
| Configuration | `/opt/ikimina-tracker/.env` (mode 0600: `DATABASE_URL`, `APP_VERSION`) and `docker-compose.yml` (image from ECR, read-only container, no capabilities, log rotation) |
| **Deploy** | `docker login` to ECR with a short-lived token → `docker compose pull` → `docker logout` → `docker compose up -d` |
| Verify | waits for `/ready` (database reachable), then checks that `/version` equals the deployed image tag |
| Clean up | prunes images older than a week |

The most important task for serving traffic is **"Log in to the private
container registry (ECR)"**, followed by the pull and `up -d`. Without the
registry login the VM can't get the image the pipeline just pushed.

The playbook is idempotent, so running it twice changes nothing the second time.

## Files

| File | In Git? | Purpose |
|------|---------|---------|
| `playbook.yml` | yes | Both plays |
| `tasks/ssh_hardening.yml` | yes | Shared SSH hardening + fail2ban tasks |
| `templates/*.j2` | yes | nginx site, sshd drop-in, production compose file, `.env` |
| `group_vars/all/main.yml` | yes | Non-secret settings (`app_port`, `bastion_subnet_cidr`, `app_subnet_cidr`, registry user, image name) |
| `group_vars/all/vault.yml` | **no**, and encrypted | `vault_database_url` for manual runs |
| `inventory/hosts.ini.example` | yes | Static inventory template (bastion + app via ProxyJump) |
| `inventory/hosts.ini` | **no** | Your real inventory |
| `requirements.yml` | yes | Pinned `community.general` collection (UFW) |

## Run it by hand

Needs Linux, macOS or WSL (Ansible doesn't run natively on Windows), with
`pip install ansible-core==2.18.6`.

```bash
# 1. Collection
ansible-galaxy collection install -r ansible/requirements.yml

# 2. Inventory: replace the example IPs with the Terraform outputs
cp ansible/inventory/hosts.ini.example ansible/inventory/hosts.ini
terraform -chdir=terraform output -raw bastion_public_ip
terraform -chdir=terraform output -raw app_private_ip

# 3. Database URL into an encrypted vault
echo "vault_database_url: \"$(terraform -chdir=terraform output -raw database_url)\"" > ansible/group_vars/all/vault.yml
ansible-vault encrypt ansible/group_vars/all/vault.yml

# 4. Registry and a short-lived pull token (12 hours); needs the AWS CLI signed in
REGISTRY=$(terraform -chdir=terraform output -raw ecr_registry)
TOKEN=$(aws ecr get-login-password --region "$(terraform -chdir=terraform output -raw aws_region)")

# 5. Check connectivity, then deploy a tag that exists in ECR (e.g. the latest main SHA)
ansible -i ansible/inventory/hosts.ini all -m ping
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbook.yml --ask-vault-pass \
  -e registry_server="$REGISTRY" -e registry_token="$TOKEN" -e image_tag="$(git rev-parse origin/main)"
```

The bastion's security group only allows SSH from `admin_cidr`. If your IP has changed,
update `admin_cidr` in `terraform.tfvars` and run `terraform apply`.

## How the CD pipeline runs it
`cd.yml` writes the same inventory from the GitHub `production` variables,
passes `registry_server`, a fresh `registry_token`, `image_tag=<commit SHA>` and
`database_url` (secret) in a temporary file with mode 0600, and runs:
```bash
ansible-playbook -i hosts.ini -e @deploy-vars.json ansible/playbook.yml
```

## Checks in CI
- **Infrastructure validation:** `ansible-playbook --syntax-check`
- **Security scan (IaC):** Checkov on the playbook (one accepted finding: the
  `http://127.0.0.1` health checks; see [../SECURITY.md](../SECURITY.md))
