# Security Policy: Ikimina Tracker

Ikimina Tracker stores savings-group balances, which are financial records.
Security is therefore checked at every stage: the application code, its
dependencies, the container image, the repository (secrets), and the
infrastructure code.

## Reporting a vulnerability
Please **do not** open a public issue. Use GitHub's
**Security → Report a vulnerability** (private advisory) on this repository,
or contact the maintainers directly. We aim to reply within 7 days.

## Automated security scanning (DevSecOps)
The CI workflow (`.github/workflows/ci.yml`) runs these on **every pull
request** and on every push to a non-`main` branch. Any failing scan turns the
check red, and branch protection blocks the merge.

| CI job | Tool | Scans | Threshold that fails the pipeline |
|--------|------|-------|-----------------------------------|
| Security scan (dependencies) | **pip-audit** 2.10.1 | Every pinned Python package in `requirements-dev.txt` (and its dependencies) against PyPA Advisory DB / OSV | **Any** known vulnerability (`--strict`) |
| Security scan (container image + secrets) | **Trivy** 0.58.1 | OS (Debian) and Python packages inside the built image | **HIGH or CRITICAL** CVEs that have a fix (`--ignore-unfixed`). MEDIUM/LOW are printed for triage but don't fail |
| ″ | **Trivy** secret scanner | Every file in the repository | **Any** detected secret (private keys, cloud/API tokens) |
| Security scan (IaC) | **Checkov** 3.4.6 | Terraform, Ansible, Dockerfile and GitHub Actions workflows | **Any** failed check, except those skipped in `.checkov.yaml` (each skip is an accepted risk below) |

Supporting jobs: `flake8`, `pytest` (incl. `tests/test_security.py`),
`terraform fmt`/`validate` and `ansible-playbook --syntax-check`.

**Why these thresholds?** Dependencies are few and pinned, so we accept no
known CVE. For the image we fail on HIGH/CRITICAL with an available fix,
because unfixed base-image CVEs can't be acted on and would block every
merge. Those are reviewed instead (see *Accepted risks*). Checkov is strict
by default, and every exception must be written down here.

## Security measures in place

**Application**
- All input validated: names are text, 1-100 characters; amounts are finite,
  positive numbers up to 1,000,000,000.
- Request bodies limited to 16 KB (larger requests get `413`).
- Errors are always JSON; unexpected errors return a generic message.
- Security headers on every response (`X-Content-Type-Options`,
  `X-Frame-Options`, `Content-Security-Policy`, `Referrer-Policy`,
  `Cache-Control: no-store`).
- Parameterised SQL only (no SQL injection). Each fix has a test in
  `tests/test_security.py`.

**Dependencies and container**
- Python dependencies pinned to exact versions; scanned by pip-audit.
- Container runs as non-root (uid 10001); `.dockerignore` keeps `.env`,
  `.git` and tests out of the image; image scanned by Trivy.
- PostgreSQL has no published port; only the app container can reach it.

**Infrastructure: Terraform (`terraform/`)**
- NSG on the **subnet**: SSH only from `admin_cidr`, API only from
  `app_allowed_cidrs`, explicit `Deny-All-Other-Inbound` rule.
- Variable validation rejects `admin_cidr = 0.0.0.0/0`, invalid CIDRs, reserved
  admin user names and non-SSH keys before anything is created.
- VM: SSH-key login only (`disable_password_authentication`), VM extensions
  disabled, Standard SKU public IP (closed unless the NSG allows traffic).
- No credentials in code (`az login`); `*.tfvars` and state are git-ignored.

**Infrastructure: Ansible (`ansible/`)**
- UFW: default-deny inbound, SSH rate-limited and only from the admin CIDR.
- SSH: no root login, no passwords, public key only, `MaxAuthTries 3`, no
  forwarding, `AllowUsers` = admin only. Validated with `sshd -t` before install.
- fail2ban bans brute-force SSH sources.
- sysctl network hardening; daily unattended security upgrades.
- Docker daemon: `no-new-privileges`, `live-restore`, log rotation.
- DB password from Ansible Vault (≥ 32 chars enforced); `.env` is `0600` and
  never logged (`no_log`).

**Repository**
- `.env`, `vault.yml`, `hosts.ini`, `*.tfvars`, state files git-ignored.
- `main` protected: PR + 1 approval + passing CI (including security scans).

## Findings log
Each finding records what was found, how it was found, its severity, and what was done about it.

| # | Date | Found by | Finding | Severity | Status / fix |
|---|------|----------|---------|----------|--------------|
| 1 | 2026-11-07 | Manual testing | Contribution amounts of `NaN` / `Infinity` accepted; one request turned every balance into `NaN` and broke JSON responses. | High | **Fixed:** amounts must be finite and ≤ 1,000,000,000. Tests: `test_rejects_nan_and_infinity`, `test_rejects_amount_above_limit` |
| 2 | 2026-11-07 | Manual testing | No size limits (1 MB group name stored; unlimited bodies). | Medium | **Fixed:** names ≤ 100 chars, bodies ≤ 16 KB. Tests: `test_rejects_long_names`, `test_rejects_huge_request_body` |
| 3 | 2026-11-07 | Manual testing | 404/405/500 returned Flask HTML; a 500 could leak internals. | Low | **Fixed:** JSON error handlers, generic 500. Tests: `test_errors_are_json`, `test_unexpected_error_hides_details` |
| 4 | 2026-11-07 | Manual testing | No HTTP security headers. | Low | **Fixed:** headers on every response. Test: `test_security_headers_on_every_response` |
| 5 | 2026-11-23 | pip-audit 2.10.1 | Scanned `requirements-dev.txt` (Flask 3.1.3, gunicorn 26.2.0, psycopg 3.3.6, pytest 9.2.0, flake8 7.5.0 + transitive): **no known vulnerabilities**. | None | No action needed. The scan now runs in CI on every PR. |
| 6 | 2026-11-23 | IaC review | Security scanning was not automated: CI had no dependency, image, secret or IaC scan. | Medium | **Fixed:** added pip-audit, Trivy (image + secrets) and Checkov jobs to CI. |
| 7 | 2026-11-23 | IaC review | NSG `Allow-API` rule allowed source `*`, with no way to restrict it per environment. | Low | **Fixed:** source is now `app_allowed_cidrs` (validated list). Default stays `0.0.0.0/0` because it is a public API; staging can be locked down. |
| 8 | 2026-11-23 | Checkov `CKV2_AZURE_31` | NSG attached only to the VM's NIC. Any VM added to the subnet later would have had **no** firewall. | Medium | **Fixed:** NSG associated with the subnet (`azurerm_subnet_network_security_group_association`), plus an explicit deny-all rule. |
| 9 | 2026-11-23 | Checkov `CKV_AZURE_50` | VM extensions were enabled, so anyone with Azure "VM Contributor" rights could run scripts as root through the Azure API, bypassing SSH controls. | Medium | **Fixed:** `allow_extension_operations = false`. Ansible over SSH is the only configuration path. |
| 10 | 2026-11-23 | IaC review | Network CIDRs and names hard-coded; nothing stopped `admin_cidr = 0.0.0.0/0`. | Low | **Fixed:** all values are variables with validation; Terraform and Ansible both refuse `0.0.0.0/0` for SSH. |
| 11 | 2026-11-23 | Playbook review | SSH relied only on the NSG: the server kept `sshd` defaults (`MaxAuthTries 6`, forwarding on, any user allowed) and had no brute-force protection. | Medium | **Fixed:** `security` role adds an `sshd_config.d` hardening drop-in (validated with `sshd -t`), UFW `limit` on SSH, and fail2ban. |
| 12 | 2026-11-23 | Playbook review | `docker compose up` task decided "changed" by reading only stdout, but Compose writes progress to **stderr**. Redeployments were reported as "ok", hiding changes from the run log / audit trail. | Low | **Fixed:** checks stdout + stderr; `--build` only when code/config changed (idempotent re-runs). |
| 13 | 2026-11-23 | Playbook review | A failed deployment ended with a bare timeout and no diagnostics. | Low | **Fixed:** `block`/`rescue` prints `docker compose ps` and logs, then fails clearly. |
| 14 | 2026-11-23 | Checkov `CKV_AZURE_119` | The VM's network interface has a public IP. | Low | **Accepted** (see *Accepted risks*); skipped inline on that one resource with the reason. |

### Automated scan results
Checkov 3.4.6 (same config as CI), before and after the infrastructure changes:

| Framework | Original F3 code | After fixes |
|-----------|------------------|-------------|
| Terraform | 12 passed, **3 failed** (`CKV_AZURE_50`, `CKV_AZURE_119`, `CKV2_AZURE_31`) | 14 passed, **0 failed**, 1 skipped (`CKV_AZURE_119`, accepted) |
| Ansible | 3 passed, 0 failed | 8 passed, 0 failed |
| Dockerfile | 48 passed, 0 failed | 48 passed, 0 failed |
| GitHub Actions | 108 passed, 0 failed | 172 passed, 0 failed |

pip-audit 2.10.1: no known vulnerabilities (finding #5).
Trivy (image + secrets) runs in CI. Its results are in the "Security scan
(container image + secrets)" job log of each run.

## Accepted risks
Each accepted risk is a decision not to fix something now, with the reason.

| Risk | Why accepted | Mitigation / when to revisit |
|------|--------------|------------------------------|
| API served over plain HTTP (no TLS) | Coursework environment with test data only; no domain or certificate yet. | Before real financial records: put Nginx/Caddy with Let's Encrypt in front and close port 5000. |
| API port open to the internet (`app_allowed_cidrs = 0.0.0.0/0`) | It is a public API by design. | Variable allows restriction per environment; app enforces validation and body-size limits. |
| `encryption_at_host_enabled = false` by default | Requires registering the `EncryptionAtHost` feature on the subscription, which student subscriptions may not allow. Managed OS disks are still encrypted at rest by Azure (SSE, platform-managed keys). | Set the variable to `true` once the feature is registered. |
| Docker-published ports bypass UFW (Docker inserts its own iptables rules) | Only the API port is published (the DB is not), and the Azure NSG, which Docker can't change, is the authoritative perimeter. | Restrict through `app_allowed_cidrs` in the NSG; add `DOCKER-USER` rules if more ports are ever published. |
| VM NIC has a public IP (Checkov `CKV_AZURE_119`) | Single-VM design with no load balancer or bastion, so the public IP is how users reach the API and how Ansible reaches the VM. A Standard-SKU public IP is closed by default, and the subnet NSG only opens SSH (admin CIDR) and the API port. | Skipped inline in `terraform/modules/compute/main.tf`. Revisit when the app moves behind a load balancer / Application Gateway and SSH goes through Azure Bastion. |
| Trivy does not fail on CVEs with no fix (`--ignore-unfixed`) or on MEDIUM/LOW | No action is possible until Debian/Python publish a fix; failing would block every merge. | MEDIUM/LOW are printed in every CI run; base image `python:3.12-slim` is rebuilt on each run, so fixes are picked up automatically. |
