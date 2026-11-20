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
- Database has no public port; it is only reachable from the app container.

**Repository**
- `.env` and secrets excluded by `.gitignore`; only `.env.example` is committed.
- `main` is protected: a pull request and all seven CI checks are required, branches must be up to date, review conversations must be resolved, and the rules also apply to administrators. Approvals are set to 0 because this is a solo project and GitHub doesn't allow self-approval.

**Infrastructure**
- Azure network security group restricts SSH to the configured administrator CIDR and is attached to both the subnet and the VM's network interface; password SSH authentication and VM extensions are disabled.
- Ansible hardens SSH (no root login, keys only, `MaxAuthTries 3`, no forwarding, `AllowUsers` the admin only; validated with `sshd -t`) and installs fail2ban.
- Only the configured API port and restricted SSH are allowed inbound; the VM also enables UFW with default-deny inbound policy.
- Terraform state, variable files, Ansible inventory, and the Ansible Vault file are excluded from Git.
- The API endpoint has no TLS by default; deploy behind a TLS-terminating reverse proxy before handling real financial records.

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

### Accepted risks
| Finding | Why it is accepted | Compensating controls | Where it is skipped |
|---------|--------------------|-----------------------|---------------------|
| #10 `CKV_AZURE_119`: public IP on the NIC | Single-VM design with no load balancer, Application Gateway or Bastion. The API must be reachable and the admin must be able to SSH in. Adding a load balancer or Bastion would multiply the cost for a student project. | NSG and UFW allow SSH **only** from `admin_cidr`, SSH is key-only and hardened, fail2ban runs, and every other port is denied. | `# checkov:skip=CKV_AZURE_119` comment in `terraform/main.tf` |
| #8 `CKV2_ANSIBLE_1`: HTTP health check | The request goes to `127.0.0.1` on the VM itself and never crosses a network, so TLS would add nothing. | None needed. | `.checkov.yaml` |
| API served over plain HTTP | No domain name or certificate yet. | **Must** be put behind a TLS-terminating reverse proxy (e.g. Caddy or nginx with Let's Encrypt) before real financial records are stored. Tracked for the summative. | n/a |
| Unfixed image CVEs are not blocking | Trivy runs with `--ignore-unfixed`: a CVE with no released fix can't be patched, and blocking on it would block every PR. | The pipeline fails as soon as a fix is published, so the next PR picks it up. | `ci.yml` (`--ignore-unfixed`) |
