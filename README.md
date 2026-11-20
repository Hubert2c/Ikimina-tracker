# Ikimina Tracker

[![CI](https://github.com/Hubert2c/Ikimina-tracker/actions/workflows/ci.yml/badge.svg)](https://github.com/Hubert2c/Ikimina-tracker/actions/workflows/ci.yml)
[![CD](https://github.com/Hubert2c/Ikimina-tracker/actions/workflows/cd.yml/badge.svg)](https://github.com/Hubert2c/Ikimina-tracker/actions/workflows/cd.yml)

> Simple, transparent digital record-keeping for community savings groups.

**Live app:** _not deployed yet. After the first deploy, put the Terraform
`app_url` output here (e.g. `http://<bastion-ip>/health`)._

This README is the operations manual: what the system is, how it is built and
deployed, and how to run, check and fix it.

| Section | |
|---|---|
| [1. The product](#1-the-product) | Problem, users, features, API |
| [2. Architecture](#2-architecture) | Diagram and how a request and a deploy flow |
| [3. Git-to-production workflow](#3-git-to-production-workflow) | Branches, CI, CD |
| [4. Run it locally](#4-run-it-locally) | Docker Compose, plain Python, tests |
| [5. Deploy to Azure (first time)](#5-deploy-to-azure-first-time) | Terraform, GitHub setup, first deploy |
| [6. Day-2 operations](#6-day-2-operations) | Health checks, logs, SSH, rollback, teardown |
| [7. Security](#7-security) | Controls and scanning |
| [8. Repository layout](#8-repository-layout) | Where everything lives |

---

## 1. The product

### Problem
Across Rwanda and much of Africa, savings groups (*ikimina*, *tontines*,
*chamas*) track member contributions in paper notebooks. Records get lost or
altered, disputes arise over who paid what, and members cannot easily check
their own balance. Ikimina Tracker gives groups a simple, auditable ledger that
any treasurer can use and that can later be reached by SMS/USSD for members
without smartphones.

### Users
- **Treasurers** who record contributions for their group
- **Members** who want to verify their balance
- Small community savings groups (10 to 30 people)

### Features
1. Create a savings group
2. Add members to a group (duplicates rejected)
3. Record a member's contribution (validated, positive amounts only)
4. View per-member balances and the group total
5. Check an individual member's balance
6. Persistent PostgreSQL storage (managed Azure Database in production)
7. Health, readiness and version endpoints, plus JSON request logs
8. *(Planned)* USSD / SMS access

### API
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Liveness: the process is up (never touches the database) |
| GET | `/ready` | Readiness: `200` when the database answers, `503` when it doesn't |
| GET | `/version` | Running build: the Git commit SHA in production, `dev` locally |
| GET | `/groups` | List groups |
| POST | `/groups` | Create group `{name}` |
| POST | `/groups/<id>/members` | Add member `{member}` |
| POST | `/groups/<id>/contributions` | Record `{member, amount}` |
| GET | `/groups/<id>` | Balances and total |
| GET | `/groups/<id>/members/<name>/balance` | One member's balance |

```bash
URL=http://localhost:5000            # or the live app URL
curl -X POST $URL/groups -H "Content-Type: application/json" -d '{"name":"Kigali Savers"}'
curl -X POST $URL/groups/1/members -H "Content-Type: application/json" -d '{"member":"Aline"}'
curl -X POST $URL/groups/1/contributions -H "Content-Type: application/json" -d '{"member":"Aline","amount":5000}'
curl $URL/groups/1
curl $URL/groups/1/members/Aline/balance
```

### Technology stack
Python 3.12, Flask, Gunicorn · PostgreSQL 16 · pytest, flake8 · Docker,
Docker Compose · GitHub Actions (CI and CD) · Terraform (Azure) · Ansible ·
pip-audit, Trivy, Checkov · nginx

---

## 2. Architecture

```mermaid
flowchart LR
    user([Treasurer / member<br/>browser or curl])
    dev([Developer])

    subgraph GH[GitHub]
        repo[(Repository<br/>main is protected)]
        ci[CI workflow<br/>lint, test, Docker build,<br/>IaC validate, pip-audit,<br/>Trivy, Checkov]
        cd[CD workflow<br/>on merge to main]
    end

    subgraph AZ["Azure resource group: ikimina-rg"]
        acr[(Azure Container<br/>Registry, private)]
        subgraph VNET["VNet 10.20.0.0/16"]
            subgraph PUB["Public subnet 10.20.1.0/24, NSG: 22 from admin, 80 from internet"]
                bastion[Bastion VM<br/>nginx reverse proxy<br/>SSH jump host]
            end
            subgraph PRIV["Private subnet 10.20.2.0/24, NSG: 22 and 5000 from bastion only"]
                app[App VM, no public IP<br/>Docker: ikimina-tracker<br/>container]
            end
            subgraph DBS["Database subnet 10.20.3.0/24, NSG: 5432 from app only"]
                db[(Azure Database for<br/>PostgreSQL, private)]
            end
        end
    end

    dev -- pull request --> repo
    repo -- every PR --> ci
    repo -- merge --> cd
    cd -- "step 1: run checks" --> ci
    cd -- "step 2: push image tagged with SHA" --> acr
    cd -- "step 3: Ansible over SSH<br/>through the bastion" --> bastion
    bastion -. ProxyJump .-> app
    app -- "docker pull" --> acr

    user -- "HTTP :80" --> bastion
    bastion -- "HTTP :5000" --> app
    app -- "TLS :5432" --> db
```

**A request:** the user calls `http://<bastion-ip>/...`. nginx on the bastion
forwards it over the private network to the container on the app VM
(`10.20.2.10:5000`). The app reads and writes the managed PostgreSQL over TLS,
on its private IP.

**A deployment:** a merged PR triggers `cd.yml`. It runs all CI checks, builds
the image, scans it with Trivy, and pushes it to ACR tagged with the commit SHA.
Then it logs in to Azure (OIDC), opens SSH on the bastion for the runner's IP
only, and runs Ansible through the bastion. Ansible pulls the new image and
runs `docker compose up -d`, then waits for `/ready` and checks that `/version`
equals the commit SHA. CD smoke-tests the public URL and closes the SSH rule
again.

| Component | Terraform file | Why it's there |
|-----------|----------------|----------------|
| VNet + 3 subnets + 3 NSGs | `terraform/network.tf` | Network segmentation: each tier only accepts traffic from the tier in front of it |
| Bastion VM (B1s, public IP) | `terraform/compute.tf` | The only public entry point: jump host for SSH and Ansible, nginx for web traffic |
| App VM (B1s, **no public IP**) | `terraform/compute.tf` | Runs the container; can't be reached from the internet |
| Azure Database for PostgreSQL (B1ms) | `terraform/database.tf` | Managed backups, patching and TLS; private access only |
| Azure Container Registry (Basic) | `terraform/registry.tf` | Private image store; admin user disabled |

---

## 3. Git-to-production workflow

1. Branch from `main`, commit, push. **CI** runs on every push.
2. Open a pull request. CI runs again, and `main`'s branch protection requires
   all seven checks to pass, review conversations to be resolved, and the branch
   to be up to date. Nobody can push to `main` directly, not even admins.
3. Merge. **CD** (`.github/workflows/cd.yml`) deploys to production
   automatically.

### CI: `.github/workflows/ci.yml` (every push and PR)
| Job | What it does | Fails when |
|-----|--------------|-----------|
| **Lint (flake8)** | Code style and errors | flake8 reports any problem |
| **Test (pytest)** | All tests on the in-memory store *and* a real PostgreSQL | any test fails |
| **Docker build** | Builds the image, starts the compose stack, writes and reads a group | the build or stack fails |
| **Infrastructure validation** | `terraform fmt -check`, `terraform validate`, `ansible-playbook --syntax-check` | any validation fails |
| **Security scan (dependencies)** | pip-audit on every Python package | any known vulnerability |
| **Security scan (container image)** | Trivy on the built image | a **HIGH or CRITICAL** CVE with a fix |
| **Security scan (IaC)** | Checkov on Terraform, Ansible, Dockerfile, workflows | any misconfiguration not documented as an accepted risk |

### CD: `.github/workflows/cd.yml` (merge to `main` only)
| Stage | Job | Steps |
|-------|-----|-------|
| 1 | **CI checks** | Calls `ci.yml`: all seven checks above |
| 2 | **Build, scan and push image to ACR** | Azure login (OIDC) → `az acr login` → `docker build` → Trivy scan of the exact image → `docker push :<sha>` and `:latest` |
| 3 | **Deploy to production (Ansible)** | Azure login → temporary NSG rule for the runner IP → Ansible through the bastion (registry login, pull, `docker compose up -d`, `/ready`, `/version`) → public smoke test → NSG rule removed (always) |

Deploys never overlap (`concurrency: deploy-production`), and the GitHub
`production` environment shows the history and the live URL.

---

## 4. Run it locally

### With Docker Compose (app + PostgreSQL)
Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).
```bash
git clone https://github.com/Hubert2c/Ikimina-tracker.git
cd Ikimina-tracker
cp .env.example .env            # then edit POSTGRES_PASSWORD in .env
docker compose up --build       # http://localhost:5000/health
```
| Task | Command |
|------|---------|
| Start in the background | `docker compose up -d --build` |
| Containers and health | `docker compose ps` |
| Follow the logs | `docker compose logs -f app` |
| Stop (data kept) | `docker compose down` |
| Stop **and delete data** | `docker compose down -v` |
| Database shell | `docker compose exec db psql -U ikimina -d ikimina` |

Only the app image (in-memory storage):
```bash
docker build -t ikimina-tracker .
docker run --rm -p 5000:5000 ikimina-tracker
```

### Plain Python
```bash
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements-dev.txt
python run.py                   # http://127.0.0.1:5000 (in-memory storage)
```

### Lint and test
```bash
flake8 .
pytest -v
TEST_DATABASE_URL=postgresql://user:pass@localhost:5432/ikimina_test pytest -v   # also on PostgreSQL
```

---

## 5. Deploy to Azure (first time)

You need: an Azure subscription (Azure for Students works),
[Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli),
[Terraform](https://developer.hashicorp.com/terraform/install) 1.6 or newer,
[GitHub CLI](https://cli.github.com), and an SSH key (`ssh-keygen -t ed25519`).
It costs about **US$1.30 a day** (2× B1s VMs, PostgreSQL B1ms, ACR Basic, 1 public IP).

**1. Sign in**
```bash
az login
az account set --subscription "<name or id>"
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
gh auth login
```

**2. Provision the infrastructure.** See [terraform/README.md](terraform/README.md).
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # set location, admin_cidr, ssh_public_key
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=tfplan     # review it
terraform -chdir=terraform apply tfplan         # about 10 to 15 minutes (PostgreSQL is the slow part)
terraform -chdir=terraform output
```

**3. Connect GitHub Actions to Azure (one time).** This creates an OIDC
identity with Contributor on the resource group only, plus the `production`
environment's variables and secrets.
```bash
bash scripts/setup-github-deploy.sh ~/.ssh/id_ed25519
```

**4. First deploy**
```bash
gh workflow run cd.yml --ref main    # or merge any PR
gh run watch
curl "$(terraform -chdir=terraform output -raw app_url)/ready"
```
Then put the URL at the top of this README.

To run Ansible by hand instead of through CD, see
[ansible/README.md](ansible/README.md).

---

## 6. Day-2 operations

| I want to… | Do this |
|------------|---------|
| Check it's alive | `curl $APP_URL/health`: the process is up |
| Check it can serve traffic | `curl $APP_URL/ready`: `200` = database reachable, `503` = it isn't |
| See which build is live | `curl $APP_URL/version`: the Git commit SHA |
| Check the proxy only | `curl $APP_URL/nginx-health` |
| SSH to the bastion | `$(terraform -chdir=terraform output -raw ssh_bastion)` |
| SSH to the app VM | `$(terraform -chdir=terraform output -raw ssh_app)` (jumps through the bastion) |
| Read app logs (one JSON line per request) | on the app VM: `sudo docker logs -f ikimina-app` |
| Container status and health | on the app VM: `sudo docker ps` (shows `healthy` / `unhealthy`) |
| Proxy logs | on the bastion: `sudo tail -f /var/log/nginx/access.log` |
| Redeploy the current `main` | `gh workflow run cd.yml --ref main` |
| **Roll back** | Revert the bad commit in a PR and merge it. CD redeploys the previous code with a new SHA |
| See deploy history | GitHub → Environments → **production** |
| Stop all charges | `terraform -chdir=terraform destroy` |

Troubleshooting:
- **`/health` OK but `/ready` 503:** the app can't reach PostgreSQL. Check the
  server is running in the Azure portal, and that `DATABASE_URL` (the GitHub
  secret) still matches `terraform output -raw database_url`.
- **502 from nginx:** the container on the app VM is down. SSH in, then run
  `sudo docker ps -a` and `sudo docker logs ikimina-app`.
- **CD fails at "Wait until the bastion accepts SSH":** the NSG rule hasn't
  propagated or the VM is stopped. Re-run the job.

---

## 7. Security
Full details, scan findings and accepted risks: [SECURITY.md](SECURITY.md).
- **Network:** only the bastion is public (SSH from the admin IP, HTTP). The app
  VM and the database have no public endpoint, and each subnet's NSG only allows
  the tier in front of it.
- **Hosts:** SSH keys only, no root login, fail2ban, UFW default-deny, VM
  extensions disabled.
- **Container:** non-root user, read-only filesystem, all Linux capabilities
  dropped, Debian security updates installed at build.
- **Secrets:** no passwords in Git. Azure login uses OIDC, the DB password is
  generated by Terraform and stored as a GitHub secret, and ACR pull tokens are
  short-lived and removed after the pull.
- **Pipeline:** pip-audit, Trivy (fails on HIGH and CRITICAL) and Checkov run on
  every PR and before every deploy.
- **Repository:** protected `main`, CODEOWNERS, `.gitignore` for state, tfvars,
  inventory and vault files.
- **Known gap:** no TLS yet (no domain). See SECURITY.md.

---

## 8. Repository layout
```
app/                      Flask app: routes.py (HTTP), services.py (logic), storage.py (memory/PostgreSQL)
tests/                    pytest suite (runs on both storage backends)
Dockerfile                image build (non-root, healthcheck, Gunicorn)
docker-compose.yml        local stack: app + PostgreSQL
terraform/                Azure infrastructure: network, compute, database, registry
ansible/                  playbook.yml, tasks/, templates/, inventory/, group_vars/
scripts/                  setup-github-deploy.sh (one-time CD setup)
.github/workflows/        ci.yml (checks), cd.yml (deploy)
.checkov.yaml, .trivyignore   scanner configuration (skips are documented in SECURITY.md)
docs/                     project board, branch protection, CI evidence, demo run sheet
SECURITY.md  CHANGELOG.md  LICENSE
```

### Collaboration
- Branch protection on `main`: [docs/BRANCH_PROTECTION.md](docs/BRANCH_PROTECTION.md)
- Project board: [GitHub Projects](https://github.com/users/Hubert2c/projects/1)
  tracking the [issues](https://github.com/Hubert2c/Ikimina-tracker/issues?q=is%3Aissue)
- CI failing, then fixed: [docs/CI_EVIDENCE.md](docs/CI_EVIDENCE.md)

## Team
Individual project by MUNEZERO Hubert ([@Hubert2c](https://github.com/Hubert2c)).
Working alone was approved in writing by the instructor.

## License
MIT, see [LICENSE](LICENSE).
