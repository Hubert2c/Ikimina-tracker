# Ansible: configure the server and deploy Ikimina Tracker

`playbook.yml` takes the bare Ubuntu VM that Terraform created
(see [../terraform/README.md](../terraform/README.md)) and turns it into a
running, hardened Ikimina Tracker server.

## What the playbook does

| Step | Tasks |
|------|-------|
| 1. Safety check | Stops early unless a vault password (32 or more characters) and `ssh_admin_cidr` are set |
| 2. Dependencies | Installs Docker, the Docker Compose plugin, Git and UFW; starts and enables Docker |
| 3. SSH hardening | Writes `/etc/ssh/sshd_config.d/10-ikimina-hardening.conf`: no root login, no passwords (keys only), max 3 tries, no forwarding, only the admin user allowed. The file is checked with `sshd -t` before it is used, so a bad setting can't lock you out. SSH restarts only when the file changes |
| 4. Brute-force protection | Installs and enables **fail2ban** |
| 5. Firewall (UFW) | Denies all inbound by default, allows SSH **only from `ssh_admin_cidr`**, allows the API port, then enables the firewall |
| 6. Deploy | Clones this repo to `/opt/ikimina-tracker`, writes `.env` (mode `0600`, secrets hidden from logs with `no_log`), runs `docker compose up --build --detach` |
| 7. Verify | Polls `http://127.0.0.1:5000/health` until the API answers 200 |

The playbook is **idempotent**, so you can run it again safely. It only changes
what differs from the desired state.

## Files

| File | In Git? | Purpose |
|------|---------|---------|
| `playbook.yml` | yes | The playbook above |
| `requirements.yml` | yes | Pinned Ansible collection (`community.general` for UFW) |
| `inventory/hosts.ini.example` | yes | Static inventory template |
| `inventory/hosts.ini` | **no** (ignored) | Your real inventory, with the VM's IP |
| `group_vars/all.yml.example` | yes | Template for non-secret variables |
| `group_vars/all.yml` | no | Your `ssh_admin_cidr` |
| `group_vars/all/vault.yml` | **no**, and encrypted | `vault_postgres_password`, encrypted with Ansible Vault |

## How to run it

### 1. Prerequisites
- Ansible (`pip install ansible-core==2.18.6`) on Linux, macOS or WSL
- The VM from Terraform, and the SSH private key that matches `ssh_public_key`

### 2. Install the collection
```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

### 3. Inventory (static)
```bash
cp ansible/inventory/hosts.ini.example ansible/inventory/hosts.ini
# replace 203.0.113.10 with: terraform -chdir=terraform output -raw public_ip
```
```ini
[app_servers]
ikimina-vm ansible_host=<public_ip> ansible_user=ikiminaadmin ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

### 4. Variables and secrets
```bash
cp ansible/group_vars/all.yml.example ansible/group_vars/all.yml
# set ssh_admin_cidr to the same value as admin_cidr in Terraform

mkdir -p ansible/group_vars/all
echo 'vault_postgres_password: "'"$(openssl rand -base64 36)"'"' > ansible/group_vars/all/vault.yml
ansible-vault encrypt ansible/group_vars/all/vault.yml   # choose a vault password
```

### 5. Check, then deploy
```bash
ansible -i ansible/inventory/hosts.ini app_servers -m ping              # can we reach the VM?
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbook.yml --syntax-check
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbook.yml --ask-vault-pass --check   # dry run
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbook.yml --ask-vault-pass
```

### 6. Confirm
```bash
curl "$(terraform -chdir=terraform output -raw api_url)"   # {"status": "ok"}
```

## Quality and security checks in CI

Every pull request runs:
- **Infrastructure validation:** `ansible-playbook --syntax-check`
- **Security scan (IaC):** Checkov on the playbook. One finding was accepted:
  the health check uses `http://127.0.0.1`, which never leaves the VM. See
  [../SECURITY.md](../SECURITY.md).
