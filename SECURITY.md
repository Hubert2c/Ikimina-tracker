# Security Policy - Ikimina Tracker

Ikimina Tracker stores savings-group balances, which are financial records,
so security is checked at every stage: in the code, in its dependencies, in the
container image and in the infrastructure code.

## Reporting a vulnerability
Please **do not** open a public issue. Use GitHub's
**Security -> Report a vulnerability** (private advisory) on this repository,
or contact the maintainers directly. We aim to reply within 7 days.

## Automated CI checks
Every push to a feature branch and every pull request into `main` runs these
jobs (`.github/workflows/ci.yml`). Branch protection requires **all seven** to
pass before a pull request can merge.

| Check | Tool | What it checks | Fails the pipeline when |
|------|------|----------------|-------------------------|
| Lint (flake8) | flake8 | Code style and errors | Any lint error |
| Test (pytest) | pytest + PostgreSQL | Behaviour, including the security tests | Any test fails |
| Docker build | Docker, Docker Compose | Image build and full-stack smoke test | Build or smoke test fails |
| Infrastructure validation | Terraform, Ansible | `terraform fmt`/`validate`, playbook syntax | Validation fails |
| **Security scan (dependencies)** | [pip-audit](https://github.com/pypa/pip-audit) 2.10.1 | Known CVEs in every pinned Python package and its dependencies | Any known vulnerability |
| **Security scan (container image)** | [Trivy](https://trivy.dev) 0.58.1 | OS (Debian) and Python packages inside the built image | A HIGH or CRITICAL CVE that has a fix |
| **Security scan (IaC)** | [Checkov](https://www.checkov.io) 3.4.6 | Terraform, Ansible playbook, Dockerfile and GitHub Actions workflows | Any failed check that isn't a documented skip |

Scanner config: `.checkov.yaml` (Checkov skips) and `.trivyignore` (empty: no
image CVEs are ignored). Every skip must be listed under *Accepted risks* below.

## Security measures in place
**Application**
- All input validated: names are text, 1-100 characters; amounts are finite,
  positive numbers up to 1,000,000,000.
- Request bodies limited to 16 KB (larger requests get `413`).
- Errors are always JSON; unexpected errors return a generic message and the
  details are only logged on the server.
- Security headers on every response: `X-Content-Type-Options`,
  `X-Frame-Options`, `Content-Security-Policy`, `Referrer-Policy`,
  `Cache-Control: no-store`.
- SQL uses parameterised queries only (no string-built SQL -> no SQL injection).
- Every fix is covered by a test in `tests/test_security.py`.

**Dependencies and container**
- All Python dependencies pinned to exact versions.
- Debian security updates are installed during the image build.
- Container runs as a non-root user (uid 10001); `.dockerignore` keeps `.env`,
  `.git` and tests out of the image.
- In production the container runs with a read-only filesystem, all Linux
  capabilities dropped and `no-new-privileges`, and its port is bound to the
  VM's private IP only.
- Images are scanned by Trivy in CI **and again in CD**, on the exact image
  that is pushed to the registry.

**Repository and pipeline**
- `.env` and secrets excluded by `.gitignore`; only `.env.example` is committed.
- `main` is protected: a pull request and all seven CI checks are required, branches must be up to date, review conversations must be resolved, and the rules also apply to administrators. Approvals are set to 0 because this is a solo project and GitHub doesn't allow self-approval.
- **No long-lived cloud credentials in GitHub:** CD logs in to Azure with
  OpenID Connect. The federated credential only trusts this repository's
  `production` environment, and the identity is Contributor on the Ikimina
  resource group only.
- Secrets (`SSH_PRIVATE_KEY`, `DATABASE_URL`) are GitHub **environment**
  secrets, available only to jobs in the `production` environment. The deploy
  writes them to a 0600 file and deletes it afterwards (`if: always()`).
- The ACR pull token is short-lived (about 3 hours), masked in logs, and
  removed from the VM (`docker logout`) right after the pull.

**Infrastructure (Azure)**
- **Network segmentation:** three subnets with an NSG each. Public: SSH only
  from `admin_cidr`, HTTP 80 from the internet. Private: SSH and 5000 only from
  the bastion subnet, everything else denied. Database: 5432 only from the app
  subnet, everything else denied.
- **No public IP on the app VM or the database.** The bastion is the single
  entry point.
- SSH to the bastion is opened for the CD runner's IP **only during a deploy**
  (a temporary NSG rule that is always removed, even if the deploy fails).
- **Managed PostgreSQL:** private access through VNet integration, public
  network access disabled, TLS required (`sslmode=require`), 7-day backups,
  connection and disconnection logging. Its 32-character password is generated
  by Terraform and never typed or committed.
- **Container registry:** admin user disabled; only Entra ID identities can
  push or pull.
- Both VMs: SSH keys only, passwords disabled, VM extensions disabled.
- Ansible hardens SSH on both VMs (no root login, keys only, `MaxAuthTries 3`,
  `AllowUsers` admin, forwarding off except `local` on the bastion for
  ProxyJump; validated with `sshd -t`), installs fail2ban, and enables UFW
  default-deny.
- nginx hides its version (`server_tokens off`) and limits bodies to 16 KB.
- Terraform state (which contains the generated DB password), tfvars, the
  Ansible inventory and the vault file are excluded from Git.

## Findings log
Each finding: what was found, how, its severity, and what we did about it.

| # | Date | Found by | Finding | Severity | Status / fix |
|---|------|----------|---------|----------|--------------|
| 1 | 2026-11-07 | Manual testing | Contribution amounts of `NaN` or `Infinity` were accepted (Python's JSON parser allows them). One bad request turned every balance and the group total into `NaN` and made API responses invalid JSON. | High | **Fixed** - amounts must be finite (`math.isfinite`) and at most 1,000,000,000. Tests: `test_rejects_nan_and_infinity`, `test_rejects_amount_above_limit` |
| 2 | 2026-11-07 | Manual testing | No size limits: a 1 MB group name was stored, and request bodies were unlimited (memory / storage exhaustion). | Medium | **Fixed** - names limited to 100 characters, request bodies to 16 KB. Tests: `test_rejects_long_names`, `test_rejects_huge_request_body` |
| 3 | 2026-11-07 | Manual testing | Errors (404, 405, 500) returned Flask's HTML pages; an unexpected error could expose internal details. | Low | **Fixed** - JSON error handlers; generic 500 message. Tests: `test_errors_are_json`, `test_unexpected_error_hides_details` |
| 4 | 2026-11-07 | Manual testing | No HTTP security headers were sent. | Low | **Fixed** - headers added to every response. Test: `test_security_headers_on_every_response` |
| 5 | 2026-11-07, 2026-11-20 | pip-audit (local, then CI) | Scanned `requirements-dev.txt`: **no known vulnerabilities**. | - | No action needed. Since 2026-11-20 this scan runs automatically on every PR. |
| 6 | 2026-11-20 | Trivy (CI, [failed run](https://github.com/Hubert2c/Ikimina-tracker/actions/runs/44797135664)) | **CVE-2026-85091** in `zlib1g` 1:1.3.dfsg+really1.3.1-1+b1 from the `python:3.12-slim` base image: heap buffer overflow in `gz_vacate()` allowing arbitrary code execution. | High | **Fixed:** the Dockerfile now runs `apt-get upgrade`, which installs the fixed version (`+deb13u1`). The rescan finds 0 HIGH/CRITICAL. |
| 7 | 2026-11-20 | Checkov `CKV2_AZURE_31` | The subnet had no network security group; only the VM's network interface did. A second VM added to the subnet would have had no firewall. | Medium | **Fixed:** `azurerm_subnet_network_security_group_association` attaches the NSG to the subnet too. |
| 8 | 2026-11-20 | Checkov `CKV2_ANSIBLE_1` | The playbook's health check uses `http://` instead of HTTPS. | Low | **Accepted:** see below. |
| 9 | 2026-11-20 | Checkov `CKV_AZURE_50` | VM extensions were allowed. Extensions run code as root on the VM and widen the attack surface. | Low | **Fixed:** `allow_extension_operations = false`. Ansible configures the VM over SSH instead. |
| 10 | 2026-11-20 | Checkov `CKV_AZURE_119` | The VM's network interface has a public IP. | Medium | **Accepted:** see below. |
| 11 | 2026-11-20 | Manual review of the playbook | SSH relied on Ubuntu defaults: root login and keyboard-interactive auth were not explicitly disabled, and there was no brute-force protection. | Medium | **Fixed:** sshd hardening drop-in plus fail2ban (see *Infrastructure* above). |
| 12 | 2026-11-20 | Checkov `CKV_AZURE_160` | Port 80 on the bastion's NSG is open to the internet. | Medium | **Accepted:** see below. |
| 13 | 2026-11-20 | Checkov `CKV2_AZURE_57` | PostgreSQL Flexible Server has no private endpoint. | - | **False positive:** the server uses VNet integration (delegated subnet, private DNS, `public_network_access_enabled = false`), the other fully private option. Skipped with a reason in `database.tf`. |
| 14 | 2026-11-20 | Checkov `CKV_AZURE_136` | PostgreSQL geo-redundant backup is off. | Low | **Accepted:** see below. |
| 15 | 2026-11-20 | Checkov `CKV_AZURE_139/163/164/165/166/167/233/237` | ACR: public network access, vulnerability scanning, content trust, geo-replication, quarantine, retention policy, zone redundancy, dedicated data endpoints. | Low | **Accepted:** all are **Premium-SKU-only** features except `CKV_AZURE_163` (scanning), which Trivy already covers before every push. See below. |
| 16 | 2026-11-20 | Architecture review (summative) | The F3 design put the app VM on a public IP (finding #10). | Medium | **Fixed:** the app VM is now in a private subnet with no public IP, and only the bastion is public. `CKV_AZURE_119` now applies only to the bastion, where a public IP is its job. |

### Accepted risks
| Finding | Why it is accepted | Compensating controls | Where it is skipped |
|---------|--------------------|-----------------------|---------------------|
| #10/#16 `CKV_AZURE_119`: public IP on the **bastion** NIC | The bastion is the single, deliberate public entry point (jump host and reverse proxy). Azure Bastion or Application Gateway would cost far more than the whole project. | NSG: SSH only from `admin_cidr` (and the CD runner, only during a deploy), HTTP 80 only. Hardened SSH, fail2ban, UFW. The app VM and the database stay private. | `# checkov:skip=CKV_AZURE_119` in `terraform/compute.tf` |
| #12 `CKV_AZURE_160`: HTTP 80 open to the internet | This is the public web entry point. There's no domain or certificate yet, so HTTPS isn't possible without a self-signed certificate. | nginx forwards only to the app's port. **Next step:** a domain plus Let's Encrypt (certbot) on nginx, then redirect 80 to 443. | `# checkov:skip=CKV_AZURE_160` in `terraform/network.tf` |
| **API served over plain HTTP** (same root cause as #12) | As above. Data between the bastion and the app VM stays on the private VNet, and the app-to-database traffic **is** TLS. | **Must** add TLS before real financial records are stored. | n/a |
| #14 `CKV_AZURE_136`: no geo-redundant DB backup | It doubles backup storage cost. A one-region outage is an acceptable risk for a student project. | 7-day point-in-time restore in the region. | `# checkov:skip=CKV_AZURE_136` in `terraform/database.tf` |
| #15 ACR Premium-only checks | Premium costs about 10× Basic. | Admin user off, Entra ID auth only, short-lived pull tokens, images Trivy-scanned before every push. | `# checkov:skip=...` lines in `terraform/registry.tf` |
| App VM outbound internet uses Azure default outbound access (no NAT gateway) | A NAT gateway costs about US$1 a day, roughly doubling the cost. It's needed only for apt, Docker and ACR pulls. | Outbound only. Inbound is still limited to the bastion subnet by the NSG and UFW. | `default_outbound_access_enabled = true` in `terraform/network.tf` |
| #8 `CKV2_ANSIBLE_1`: HTTP health checks | The requests go to `127.0.0.1` on the VM itself and never cross a network. | None needed. | `.checkov.yaml` |
| Unfixed image CVEs are not blocking | Trivy runs with `--ignore-unfixed`: a CVE with no released fix can't be patched, and blocking on it would block every PR. | The pipeline fails as soon as a fix is published, so the next PR picks it up. | `ci.yml` and `cd.yml` (`--ignore-unfixed`) |
| Docker-published ports bypass UFW | Docker writes its own iptables rules, so UFW doesn't filter port 5000 on the app VM. | The port is bound to the private IP only, and the Azure NSG (enforced outside the VM) allows 5000 only from the bastion subnet. | n/a |
