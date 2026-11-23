# Ikimina Tracker

![CI](https://github.com/<YOUR-GITHUB-USERNAME>/ikimina-tracker/actions/workflows/ci.yml/badge.svg)

> Simple, transparent digital record-keeping for community savings groups.

## Problem Statement
Across Rwanda and much of Africa, savings groups (*ikimina*, *tontines*, *chamas*)
track member contributions in paper notebooks. Records get lost or altered,
disputes arise over who paid what, and members cannot easily check their own
balance. Ikimina Tracker gives groups a simple, auditable ledger that any
treasurer can use and that can later be reached by SMS/USSD for members
without smartphones.

## Target Users
- **Treasurers** who record contributions for their group
- **Members** who want to verify their balance
- Small community savings groups (10-30 people)

## Core Features
1. Create a savings group
2. Add members to a group (duplicates rejected)
3. Record a member's contribution (validated, positive amounts only)
4. View per-member balances and the group total
5. Check an individual member's balance
6. Persistent PostgreSQL storage (when run with Docker Compose)
7. *(Planned)* USSD / SMS access

## Technology Stack
- Python 3.12, Flask (REST API), Gunicorn (production server)
- PostgreSQL 16 (persistent storage), in-memory store for tests
- pytest (tests), flake8 (linting)
- Docker + Docker Compose (containers), GitHub Actions (CI)
- Azure VM deployment (Terraform provisioning, Ansible configuration)

## Project Structure
```
app/
  __init__.py   # application factory
  routes.py     # HTTP layer only
  services.py   # business logic and validation
  storage.py    # data layer: in-memory store + PostgreSQL store
tests/          # pytest tests (conftest.py runs them on both stores)
docs/           # planning, security and board documentation
.github/workflows/ci.yml   # CI pipeline
terraform/                 # Azure VM and network provisioning
ansible/                   # Docker host setup and application deployment
Dockerfile                 # how the app image is built
docker-compose.yml         # app + database, started together
.dockerignore              # files kept out of the image
run.py                     # entry point
```
Routes, business logic and storage are separated so each can evolve into its
own service (e.g. a ledger service and a notification/USSD service).

## Running with Docker Compose (recommended)
Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/)
(or Docker Engine + the Compose plugin).

```bash
git clone <your-repo-url>
cd ikimina-tracker
cp .env.example .env            # then edit POSTGRES_PASSWORD in .env
docker compose up --build       # builds the image and starts app + database
```
The API is now at http://localhost:5000 (try `curl localhost:5000/health`).

| Task | Command |
|------|---------|
| Start in the background | `docker compose up -d --build` |
| See running containers and health | `docker compose ps` |
| Follow the logs | `docker compose logs -f app` |
| Stop (data is kept) | `docker compose down` |
| Stop **and delete all data** | `docker compose down -v` |
| Open a database shell | `docker compose exec db psql -U ikimina -d ikimina` |

How it fits together:
- **app** is built from the `Dockerfile` (Python 3.12-slim, runs as a non-root
  user, served by Gunicorn) and published on port 5000.
- **db** is PostgreSQL 16. It is only reachable from the app over the private
  `ikimina-net` network; its files live in the `pgdata` volume, so data survives
  restarts.
- The app finds the database through the `DATABASE_URL` environment variable,
  built from the values in `.env`. It waits for the database health check
  before starting.

Build and run only the app image (in-memory storage, no database):
```bash
docker build -t ikimina-tracker .
docker run --rm -p 5000:5000 ikimina-tracker
```

## Running Locally without Docker
Uses in-memory storage unless you set `DATABASE_URL`.
```bash
git clone <your-repo-url>
cd ikimina-tracker
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements-dev.txt
python run.py                   # http://127.0.0.1:5000
```

### Lint and test
```bash
flake8 .                        # style and error checks
pytest -v                       # tests on the in-memory store
# Also test on PostgreSQL (e.g. with the compose db exposed or your own server):
TEST_DATABASE_URL=postgresql://user:pass@localhost:5432/ikimina_test pytest -v
```

## Continuous Integration
`.github/workflows/ci.yml` runs on every push to any branch except `main`,
and on every pull request:

| Job | What it does | Fails when |
|-----|--------------|-----------|
| **Lint (flake8)** | Checks code style and errors | flake8 reports any problem |
| **Test (pytest)** | Runs all tests on the in-memory store *and* a real PostgreSQL service | any test fails |
| **Docker build** | Builds the image, starts the full compose stack, calls `/health`, writes and reads a group | the build fails or the stack doesn't work |
| **Infrastructure validation** | Checks Terraform formatting and configuration, and Ansible playbook syntax | any validation fails |
| **Security scan (dependencies)** | pip-audit checks every pinned Python package for known CVEs | any known vulnerability |
| **Security scan (container image + secrets)** | Trivy scans the built image and the repo for committed secrets | a fixable HIGH/CRITICAL CVE or any secret |
| **Security scan (IaC)** | Checkov scans Terraform, Ansible, the Dockerfile and workflows | any failed (non-skipped) check |

`Docker build` only runs after lint and tests pass. Branch protection on `main`
requires all of these checks, so a pull request cannot be merged while CI is red.

### Azure VM deployment
Terraform provisions the infrastructure on Azure: a virtual network, a subnet,
a network security group, and an Ubuntu 24.04 VM with a static public IP. It is
split into `network` and `compute` modules. Ansible then hardens the VM and
deploys the containerized app, using the roles `common`, `security`, `docker`
and `app`.

1. **Provision:** follow [terraform/README.md](terraform/README.md)
   (`az login`, copy `terraform.tfvars.example`, `terraform init`, `plan`, `apply`).
2. **Configure and deploy:** follow [ansible/README.md](ansible/README.md)
   (static or Azure dynamic inventory, Vault-encrypted DB password,
   `ansible-playbook playbook.yml --ask-vault-pass`).

SSH is limited to your admin CIDR by both the Azure NSG and UFW, and the server
is hardened with key-only SSH, fail2ban and sysctl settings. The app is served
on port 5000 without TLS (an accepted risk, see [SECURITY.md](SECURITY.md));
put it behind a TLS-terminating reverse proxy before storing real financial
records.

### Example usage
```bash
curl -X POST localhost:5000/groups -H "Content-Type: application/json" -d '{"name":"Kigali Savers"}'
curl -X POST localhost:5000/groups/1/members -H "Content-Type: application/json" -d '{"member":"Aline"}'
curl -X POST localhost:5000/groups/1/contributions -H "Content-Type: application/json" -d '{"member":"Aline","amount":5000}'
curl localhost:5000/groups/1
curl localhost:5000/groups/1/members/Aline/balance
```

## API Reference
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/groups` | List groups |
| POST | `/groups` | Create group `{name}` |
| POST | `/groups/<id>/members` | Add member `{member}` |
| POST | `/groups/<id>/contributions` | Record `{member, amount}` |
| GET | `/groups/<id>` | Balances and total |
| GET | `/groups/<id>/members/<name>/balance` | One member's balance |

## Security & Collaboration Practices
- `.gitignore` excludes secrets, virtual environments, IDE files and build artifacts
- `.dockerignore` keeps `.env`, `.git` and tests out of the image
- Container runs as a non-root user (uid 10001); the database has no public port
- Dependencies pinned to exact versions for reproducible builds
- Branch protection on `main` with required CI checks (see [docs/BRANCH_PROTECTION.md](docs/BRANCH_PROTECTION.md))
- All changes go through pull requests with review
- Project board: see [docs/PROJECT_BOARD.md](docs/PROJECT_BOARD.md)


## License
MIT, see [LICENSE](LICENSE).

MUNEZERO Hubert
