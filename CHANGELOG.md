# Changelog

How Ikimina Tracker evolved across the course. Format based on
[Keep a Changelog](https://keepachangelog.com/). Newest first.

## [Summative] - 2026-11 - Git-to-production pipeline
<!-- Fill in each line as YOUR work lands. Delete lines you don't do. -->
### Added
- Observability endpoints: `/ready` (checks the database, returns 503 when
  it's unreachable) and `/version` (reports the deployed build via
  `APP_VERSION`), plus one JSON log line per request (method, path, status,
  duration) on stdout.
- <!-- Terraform: private VNet, private + public subnets, app VM in the private subnet -->
- <!-- Terraform: bastion host in the public subnet -->
- <!-- Terraform: managed PostgreSQL (Azure Database for PostgreSQL) -->
- <!-- Terraform: private container registry (ACR) -->
- <!-- CI: container image scan (e.g. Trivy) and IaC scan (e.g. Checkov), failing on CRITICAL -->
- <!-- CD: cd.yml on merge to main - CI checks, push image to ACR, run Ansible -->
- <!-- Live URL: ... -->
### Changed
- <!-- Database moved from the compose `db` container to the managed database -->
- <!-- VM no longer has a public IP; reached through the bastion -->
- <!-- Ansible now pulls the image from ACR instead of building on the server -->
### Security
- <!-- scan findings fixed or accepted - see SECURITY.md -->

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
