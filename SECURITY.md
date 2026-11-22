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
- **No long-lived cloud credentials in GitHub:** CD logs in to AWS with
  OpenID Connect and assumes an IAM role (`terraform/github_oidc.tf`). The role
  trusts only this repository's `production` environment, and its policy allows
  only pushing to the Ikimina ECR repository and adding/removing SSH rules on
  the bastion's security group.
- Secrets (`SSH_PRIVATE_KEY`, `DATABASE_URL`) are GitHub **environment**
  secrets, available only to jobs in the `production` environment. The deploy
  writes them to a 0600 file and deletes it afterwards (`if: always()`).
- The ECR pull token is short-lived (12 hours), masked in logs, and removed
  from the VM (`docker logout`) right after the pull.

**Infrastructure (AWS)**
- **Network segmentation:** public, private and database subnets, each tier
  with its own security group. Bastion: SSH only from `admin_cidr`, HTTP 80
  from the internet. App: SSH and 5000 only from the bastion's security group.
  Database: 5432 only from the app's security group, no egress. The VPC's
  default security group is emptied.
- **No public IP on the app VM or the database.** The bastion is the single
  entry point. The database subnets have no route to the internet.
- SSH to the bastion is opened for the CD runner's IP **only during a deploy**
  (a temporary security group rule that is always removed, even if the deploy
  fails).
- **Managed PostgreSQL (RDS):** `publicly_accessible = false`, storage
  encrypted, TLS enforced on the server (`rds.force_ssl = 1`) and by the client
  (`sslmode=require`), automated backups, connection and disconnection logging
  exported to CloudWatch. Its 32-character password is generated by Terraform
  and never typed or committed.
- **Container registry (ECR):** private, scan on push, only the 10 newest
  images kept. Only the GitHub deploy role can push.
- Both VMs: SSH keys only, passwords disabled, IMDSv2 required, encrypted
  disks, and **no IAM role**, so a compromised VM holds no AWS credentials.
- Ansible hardens SSH on both VMs (no root login, keys only, `MaxAuthTries 3`,
  `AllowUsers` admin, forwarding off except `local` on the bastion for
  ProxyJump; validated with `sshd -t`), installs fail2ban, and enables UFW
  default-deny. On the bastion, UFW forwards only traffic from the app subnet
  (NAT).
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
| 7 | 2026-11-20 | Checkov `CKV2_AZURE_31` | The subnet had no network security group; only the VM's network interface did. A second VM added to the subnet would have had no firewall. | Medium | **Fixed:** `azurerm_subnet_network_security_group_association` attaches the NSG to the subnet too. *(Azure; superseded by #17)* |
| 8 | 2026-11-20 | Checkov `CKV2_ANSIBLE_1` | The playbook's health check uses `http://` instead of HTTPS. | Low | **Accepted:** see below. |
| 9 | 2026-11-20 | Checkov `CKV_AZURE_50` | VM extensions were allowed. Extensions run code as root on the VM and widen the attack surface. | Low | **Fixed:** `allow_extension_operations = false`. Ansible configures the VM over SSH instead. *(Azure; superseded by #17)* |
| 10 | 2026-11-20 | Checkov `CKV_AZURE_119` | The VM's network interface has a public IP. | Medium | **Accepted:** see below. *(Azure; superseded by #17)* |
| 11 | 2026-11-20 | Manual review of the playbook | SSH relied on Ubuntu defaults: root login and keyboard-interactive auth were not explicitly disabled, and there was no brute-force protection. | Medium | **Fixed:** sshd hardening drop-in plus fail2ban (see *Infrastructure* above). |
| 12 | 2026-11-20 | Checkov `CKV_AZURE_160` | Port 80 on the bastion's NSG is open to the internet. | Medium | **Accepted:** see below. *(Azure; superseded by #17)* |
| 13 | 2026-11-20 | Checkov `CKV2_AZURE_57` | PostgreSQL Flexible Server has no private endpoint. | - | **False positive:** the server uses VNet integration (delegated subnet, private DNS, `public_network_access_enabled = false`), the other fully private option. Skipped with a reason in `database.tf`. *(Azure; superseded by #17)* |
| 14 | 2026-11-20 | Checkov `CKV_AZURE_136` | PostgreSQL geo-redundant backup is off. | Low | **Accepted:** see below. *(Azure; superseded by #17)* |
| 15 | 2026-11-20 | Checkov `CKV_AZURE_139/163/164/165/166/167/233/237` | ACR: public network access, vulnerability scanning, content trust, geo-replication, quarantine, retention policy, zone redundancy, dedicated data endpoints. | Low | **Accepted:** all are **Premium-SKU-only** features except `CKV_AZURE_163` (scanning), which Trivy already covers before every push. See below. *(Azure; superseded by #17)* |
| 16 | 2026-11-20 | Architecture review (summative) | The F3 design put the app VM on a public IP (finding #10). | Medium | **Fixed:** the app VM is now in a private subnet with no public IP, and only the bastion is public. `CKV_AZURE_119` now applies only to the bastion, where a public IP is its job. *(Azure; superseded by #17)* |
| 17 | 2026-11-22 | Architecture change | The project moved from Azure to AWS because no Azure subscription was available. Azure-specific findings #7, #9, #10 and #12 to #16 no longer apply; their AWS equivalents are #18 to #27. | - | **Done:** same design (bastion, private app VM, managed DB, private registry, OIDC deploys) rebuilt with AWS resources. |
| 18 | 2026-11-22 | Checkov `CKV_AWS_260` | Port 80 on the bastion's security group is open to the internet. | Medium | **Accepted:** see below (same as #12). |
| 19 | 2026-11-22 | Checkov `CKV_AWS_24` | Reported SSH open to 0.0.0.0/0 on the app VM's rule. | - | **False positive:** the rule's source is the bastion's security group (`referenced_security_group_id`), not an address range. Skipped with a reason in `network.tf`. |
| 20 | 2026-11-22 | Checkov `CKV_AWS_382` | The bastion and app security groups allow all outbound traffic. | Low | **Accepted:** see below. |
| 21 | 2026-11-22 | Checkov `CKV2_AWS_41` | The EC2 instances have no IAM role. | - | **Accepted by design:** the VMs never call AWS APIs, so giving them no role means a compromised VM holds no AWS credentials. |
| 22 | 2026-11-22 | Checkov `CKV_AWS_126` | Detailed (1-minute) EC2 monitoring is off. | Low | **Accepted:** paid add-on; basic 5-minute metrics are kept. |
| 23 | 2026-11-22 | Checkov `CKV_AWS_157/118/353/161/293`, `CKV2_AWS_30` | RDS: no Multi-AZ, enhanced monitoring, Performance Insights, IAM auth, deletion protection or query logging. | Low | **Accepted:** see below. |
| 24 | 2026-11-22 | Checkov `CKV_AWS_51/136` | ECR: mutable tags, AWS-managed (not KMS) encryption. | Low | **Accepted:** see below. |
| 25 | 2026-11-22 | Checkov `CKV2_AWS_11` | No VPC flow logs. | Low | **Accepted:** see below. |
| 26 | 2026-11-22 | Checkov `CKV_AWS_356` | The deploy policy uses `Resource: "*"`. | - | **Accepted:** only for `ecr:GetAuthorizationToken`, which AWS supports on `*` only. Every other action is limited to the ECR repository or the bastion's security group. |
| 27 | 2026-11-22 | Checkov `CKV_AWS_394` | The availability zone lookup isn't pinned to zone IDs. | Low | **Accepted:** only the first two zones are used, and any change would show in `terraform plan` before being applied. |

### Accepted risks
| Finding | Why it is accepted | Compensating controls | Where it is skipped |
|---------|--------------------|-----------------------|---------------------|
| Public IP (Elastic IP) on the **bastion** | The bastion is the single, deliberate public entry point (jump host and reverse proxy). A load balancer or a Systems Manager setup would cost more or add complexity beyond this project. | Security group: SSH only from `admin_cidr` (and the CD runner, only during a deploy), HTTP 80 only. Hardened SSH, fail2ban, UFW. The app VM and the database stay private. | n/a (`aws_eip.bastion` in `terraform/compute.tf`) |
| #18 `CKV_AWS_260`: HTTP 80 open to the internet | This is the public web entry point. There's no domain or certificate yet, so HTTPS isn't possible without a self-signed certificate. | nginx forwards only to the app's port. **Next step:** a domain plus Let's Encrypt (certbot) on nginx, then redirect 80 to 443. | `# checkov:skip=CKV_AWS_260` in `terraform/network.tf` |
| **API served over plain HTTP** (same root cause as #18) | As above. Data between the bastion and the app VM stays inside the VPC, and the app-to-database traffic **is** TLS. | **Must** add TLS before real financial records are stored. | n/a |
| #23 RDS: single-AZ, no enhanced monitoring, Performance Insights, IAM auth, deletion protection or query logging | Multi-AZ doubles the database cost; the others are paid add-ons or would need AWS credentials on the VM (IAM auth). Deletion protection is off so `terraform destroy` stops all costs. | Automated backups with point-in-time restore (1 day on the free tier, configurable to 7), encryption at rest, enforced TLS, connection logging, no public access. | `# checkov:skip=...` lines in `terraform/database.tf` |
| #24 ECR: mutable tags, AWS-managed encryption | The pipeline moves the `latest` tag, so tags can't be immutable; a customer-managed KMS key adds cost without benefit here. | Deploys always use the commit-SHA tag, images are scanned on push and by Trivy before every push, and only the deploy role can push. | `# checkov:skip=...` lines in `terraform/registry.tf` |
| The bastion doubles as the NAT for the private subnet (no NAT gateway) | A managed NAT gateway costs about US$32 a month, more than the rest of the environment. It's needed only for apt, Docker and ECR pulls. | NAT forwards outbound traffic from the app subnet only (iptables and a UFW route rule). Inbound to the app VM is still limited to the bastion by its security group and UFW. If the bastion is down, the site is down anyway. | `terraform/templates/bastion-nat.sh.tftpl`, `aws_route_table.private` |
| #20 `CKV_AWS_382`: unrestricted egress on the bastion and app VM | The NAT and the app must reach package mirrors, Docker Hub and ECR, whose addresses change. | No IAM credentials on either VM; the database security group has no egress at all. | `# checkov:skip=CKV_AWS_382` in `terraform/network.tf` |
| #25 `CKV2_AWS_11`: no VPC flow logs | They add CloudWatch cost. | Security groups and UFW block unexpected traffic; nginx and the app log every request. **Next step** if this held real data. | `# checkov:skip=CKV2_AWS_11` in `terraform/network.tf` |
| #8 `CKV2_ANSIBLE_1`: HTTP health checks | The requests go to `127.0.0.1` on the VM itself and never cross a network. | None needed. | `.checkov.yaml` |
| Unfixed image CVEs are not blocking | Trivy runs with `--ignore-unfixed`: a CVE with no released fix can't be patched, and blocking on it would block every PR. | The pipeline fails as soon as a fix is published, so the next PR picks it up. | `ci.yml` and `cd.yml` (`--ignore-unfixed`) |
| Docker-published ports bypass UFW | Docker writes its own iptables rules, so UFW doesn't filter port 5000 on the app VM. | The port is bound to the private IP only, and the AWS security group (enforced outside the VM) allows 5000 only from the bastion. | n/a |
