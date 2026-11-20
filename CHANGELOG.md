# Changelog

How Ikimina Tracker evolved across the course. Format based on
[Keep a Changelog](https://keepachangelog.com/). Newest first.

## [Summative] - 2026-11 - Git-to-production pipeline
### Added
- **Production infrastructure (Terraform)**, split into `network.tf`,
  `compute.tf`, `database.tf`, `registry.tf`, `variables.tf` and `outputs.tf`:
  - VNet with **public**, **private** and **database** subnets, each with its
    own NSG. Each tier accepts traffic only from the tier in front of it.
  - **Bastion host** in the public subnet: SSH jump host and nginx reverse
    proxy that serves the public URL.
  - **App VM in the private subnet** with no public IP.
  - **Azure Database for PostgreSQL** Flexible Server (16, B1ms): private
    access only, TLS, 7-day backups, connection logging, generated password.
  - **Azure Container Registry** (private, admin user disabled).
  - Outputs for the URL, IPs, SSH commands, registry, sensitive DB URL and
    resource IDs.
- **CD pipeline** `.github/workflows/cd.yml` ("Deploy to Production"), on merge
  to `main` only: runs the full CI workflow, builds and Trivy-scans the image,
  pushes it to ACR tagged with the commit SHA, logs in to Azure with **OIDC**,
  opens SSH on the bastion for the runner's IP only, runs Ansible through the
  bastion, smoke-tests the live URL, and always closes SSH again. Deploys never
  overlap.
- `scripts/setup-github-deploy.sh`: one-time setup of the Azure identity
  (federated credential, Contributor on the resource group only) and the
  GitHub `production` environment's variables and secrets.
- Ansible play for the **bastion**: nginx reverse proxy, UFW, hardened SSH
  (with forwarding for ProxyJump), fail2ban.
- Observability: `/ready` (checks the database, returns 503 when it's
  unreachable) and `/version` (reports the deployed commit SHA via
  `APP_VERSION`), plus one JSON log line per request (method, path, status,
  duration) on stdout. CD and Ansible use them to verify each deploy.
- README rewritten as the operations manual, with an architecture diagram,
  deploy steps, day-2 operations and troubleshooting.
- `docs/DEMO_RUNSHEET.md`: commands for each of the 10 demo prompts.
### Changed
- **Database moved from the Compose `db` container to the managed Azure
  Database for PostgreSQL** in production (the local `docker-compose.yml`
  still runs its own PostgreSQL for development).
- **The app VM no longer has a public IP.** It is reached only through the
  bastion (Ansible uses ProxyJump; public traffic goes through nginx).
- **Ansible now pulls the image from ACR** instead of cloning the repo and
  building on the server. The production Compose file runs only the app
  container, read-only, with no Linux capabilities and log rotation.
- `ci.yml` can be called by other workflows (`workflow_call`), so CD reuses
  exactly the same checks.
### Security
- Checkov on the new Terraform: 34 passed, 0 failed, 12 documented skips
  (bastion public IP, HTTP 80 without a domain, geo-redundant backup, ACR
  Premium-only features, and a false positive for the DB private endpoint).
  Details and justifications in `SECURITY.md` (findings #12 to #16).
- No long-lived Azure credentials in GitHub (OIDC), environment-scoped
  secrets, short-lived registry tokens removed from the VM after each pull.

## [Formative 3] - 2026-11-07 - Infrastructure as Code & DevSecOps
### Added
- Terraform for Azure: resource group, virtual network and subnet, network
  security group (SSH only from an admin CIDR, API port open), public IP and
  an Ubuntu 24.04 VM with SSH-key-only login. Variables for all
  environment-specific values; outputs for the public IP and SSH command.
- Ansible playbook: installs Docker, Compose, Git and UFW; firewall with
  default-deny inbound; checks out the app, writes a `0600` `.env` from Ansible
  Vault, starts the stack with `docker compose up` and waits for `/health`.
- CI job "Infrastructure validation": `terraform fmt`/`validate` and Ansible
  syntax check.
- `SECURITY.md`: vulnerability reporting policy, security measures, findings log.
- (Added 2026-11-20, after F3 feedback) DevSecOps scans in CI on every PR:
  pip-audit (dependencies), Trivy (container image, fails on HIGH/CRITICAL),
  Checkov (Terraform, Ansible, Dockerfile, workflows). Fixed findings: a HIGH
  zlib CVE in the base image (Debian updates in the Dockerfile), a subnet
  without an NSG, and VM extensions allowed. Added SSH hardening with fail2ban,
  and READMEs for Terraform and Ansible.
### Security
- Rejected `NaN`/`Infinity` contribution amounts, which corrupted every
  balance in a group (High).
- Added length limits on names and a 16 KB request-body limit (Medium).
- Errors are always JSON; unexpected errors hide internal details (Low).
- Security headers on every response (Low).
- `.gitignore` extended for Terraform variable files, Ansible inventory and Vault.

## [Formative 2] - 2026-10-30 - Containerization & CI
### Added
- PostgreSQL storage (`PostgresStore`), chosen with `DATABASE_URL`; in-memory
  store kept for tests. Tests run against both.
- `Dockerfile` (Python 3.12-slim, non-root user, Gunicorn, health check),
  `.dockerignore`.
- `docker-compose.yml`: app + PostgreSQL 16 on a private network with a
  named volume; one command to run locally.
- GitHub Actions CI: lint (flake8) -> tests (pytest + PostgreSQL service) ->
  Docker build and compose smoke test.
### Changed
- Dependencies pinned to exact versions; dev tools split into
  `requirements-dev.txt`.
- App served by Gunicorn instead of Flask's development server.
- (2026-11-20, after F2 feedback) Branch protection now really requires the
  CI checks. Evidence of a failing run that blocked a merge, a review, and the
  fix: PR #22 and `docs/CI_EVIDENCE.md`.

## [Formative 1] - 2026-10-23 - Project foundation
### Added
- Flask REST API for savings groups (*ikimina*): create groups, add members,
  record contributions, view balances and group totals.
- Layered structure: routes (HTTP) / services (business rules) / storage
  (data), so each part can later become its own service.
- Input validation (positive amounts, known members, no duplicate members)
  and unit tests.
- `.gitignore`, MIT licence, CODEOWNERS, `.env.example`.
- Project board, branch protection documentation, README.
- (2026-11-20, after F1 feedback) Real GitHub Projects board and issues,
  branch protection enabled on `main`, placeholders in LICENSE and CODEOWNERS
  filled in. All changes now go through pull requests.
