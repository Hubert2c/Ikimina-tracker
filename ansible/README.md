# Ansible: configure the server and deploy Ikimina Tracker

The playbook takes the fresh Ubuntu VM created by
[Terraform](../terraform/README.md) and turns it into a hardened Docker host
running the API and PostgreSQL.

```text
ansible/
├── ansible.cfg                  # defaults when run from this directory
├── playbook.yml                 # applies the four roles below
├── requirements.yml             # collections: community.general, ansible.posix, azure.azcollection
├── inventory/
│   ├── hosts.ini.example        # static inventory (copy to hosts.ini)
│   └── azure_rm.yml             # dynamic inventory (finds VMs by tag)
├── group_vars/all/
│   ├── main.yml                 # non-secret settings (admin CIDR, port, revision)
│   └── vault.yml.example        # secret DB password, encrypt with ansible-vault
└── roles/
    ├── common/                  # apt cache, base tools, automatic security updates
    ├── security/                # UFW, SSH hardening, fail2ban, sysctl hardening
    ├── docker/                  # Docker Engine + Compose, hardened daemon.json
    └── app/                     # git checkout, .env, compose up, health check
```

## What each role does

| Role | Tasks |
|------|-------|
| **common** | Installs `git`, `curl`, `ca-certificates`, `unattended-upgrades`. Turns on daily automatic security updates |
| **security** | **Firewall (UFW):** default deny inbound, SSH only from `ssh_admin_cidr` (rate-limited with `limit`), API port from `app_allowed_cidrs`, logging on. SSH is allowed *before* UFW is enabled, so you can't lock yourself out. **SSH hardening** (`/etc/ssh/sshd_config.d/10-ikimina-hardening.conf`): no root login, no passwords, public-key only, `MaxAuthTries 3`, no X11/agent/TCP forwarding, `AllowUsers` = the admin user only. `sshd -t` validates the file before it is installed. **fail2ban:** bans an IP for 1 h after 5 failed SSH logins in 10 min (your admin CIDR is never banned). **Kernel hardening (sysctl):** no ICMP redirects or source routing, SYN cookies, log martian packets, restrict `dmesg` |
| **docker** | Installs `docker.io` + `docker-compose-v2`. `daemon.json`: `no-new-privileges`, `live-restore`, log rotation (10 MB × 3) |
| **app** | Checks the Vault password is set (≥ 32 chars). Clones the repo at `app_revision`. Writes `.env` (mode `0600`, `no_log`). Runs `docker compose up --wait`, then polls `/health` |

### Idempotency and error handling

- All tasks use declarative modules (`apt`, `template`, `ufw`, `sysctl`,
  `service`, `git`). The only `command` task (`docker compose up`) has a
  `changed_when`, and it adds `--build` only when the code or `.env` changed.
  **A second run reports `changed=0`.**
- Handlers restart SSH / fail2ban / Docker only when their config changed.
- `assert` tasks stop the run early with a clear message if the OS isn't
  Ubuntu 22.04+, `ssh_admin_cidr` is `0.0.0.0/0`, or the DB password is weak.
- The deployment is a `block` / `rescue`. If the stack doesn't become healthy,
  the rescue prints `docker compose ps` and the last 50 log lines, then fails
  with a clear message, so you don't have to SSH in to debug.

## Prerequisites

- A Linux/macOS/WSL control machine with Python 3 (Ansible doesn't run
  natively on Windows. Use WSL there.)
- The VM created by Terraform, and the private key matching `ssh_public_key`

```bash
cd ansible
python3 -m pip install ansible-core==2.18.6
ansible-galaxy collection install -r requirements.yml
```

## 1. Inventory

Two options are available.

**Static** (simplest). Generate it from Terraform's output:

```bash
terraform -chdir=../terraform output -raw ansible_inventory > inventory/hosts.ini
# or: cp inventory/hosts.ini.example inventory/hosts.ini and edit the IP
```

**Dynamic** (no IPs to copy). It asks Azure for every VM tagged
`application=ikimina-tracker`:

```bash
pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt
az login
ansible-inventory -i inventory/azure_rm.yml --graph   # shows the app_servers group
```

## 2. Variables and secrets

```bash
# Your IP with /32: the only address allowed to SSH in (same as Terraform's admin_cidr)
#   edit group_vars/all/main.yml  ->  ssh_admin_cidr: "x.x.x.x/32"

cp group_vars/all/vault.yml.example group_vars/all/vault.yml
#   set vault_postgres_password to: openssl rand -base64 48
ansible-vault encrypt group_vars/all/vault.yml
```

`vault.yml` and `hosts.ini` are git-ignored.

## 3. Run the playbook

```bash
cd ansible

# Check connectivity
ansible app_servers -m ansible.builtin.ping

# Dry run: show what would change
ansible-playbook playbook.yml --ask-vault-pass --check --diff

# Apply (static inventory from ansible.cfg)
ansible-playbook playbook.yml --ask-vault-pass

# ...or with the dynamic inventory
ansible-playbook -i inventory/azure_rm.yml playbook.yml --ask-vault-pass

# Run one part only, e.g. re-deploy the app
ansible-playbook playbook.yml --ask-vault-pass --tags app   # roles are tagged common / security / docker / app
```

Deploy a different revision: `-e app_revision=<branch-or-tag>`.

## 4. Verify

```bash
curl http://<public_ip>:5000/health            # {"status": "ok"}
ssh ikiminaadmin@<public_ip> 'sudo ufw status verbose; sudo fail2ban-client status sshd'
ssh -o PubkeyAuthentication=no ikiminaadmin@<public_ip>   # refused: password login disabled
```

## CI checks

Every push and pull request runs `ansible-playbook --syntax-check`
("Infrastructure validation" job), and Checkov scans the playbook and roles
("Security scan (IaC)" job).
