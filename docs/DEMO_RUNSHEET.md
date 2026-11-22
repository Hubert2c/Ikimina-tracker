# Summative demo run sheet

Your own checklist for recording the demo video. **Don't read it on camera**:
the brief asks for natural narration, not a script. Use it to prepare, then
glance at the commands while recording.

- **YouTube title:** `MUNEZERO Hubert - Amani Market Systems - Summative Demo`
- **Visibility:** Unlisted. Test the link in a private or incognito window.
- **Length:** 10 to 15 minutes (assessors stop at 18). 720p or higher. Webcam overlay on.
- **Upload:** at least 24 hours before the deadline.
- **Submit:** the YouTube link plus the summative PR URL
  (https://github.com/Hubert2c/Ikimina-tracker/pull/3).

## Before you hit record
- [ ] AWS environment is up (`terraform -chdir=terraform output app_url`)
      and `curl $APP_URL/ready` returns 200.
- [ ] One full CD run has already succeeded (a fallback if a live run is slow).
- [ ] A small branch is ready to merge for Prompt 8 (e.g. a README wording
      change), with its PR open and CI green.
- [ ] Docker Desktop is running.
- [ ] Terminal, IDE and browser font size increased (zoom about 150%).
- [ ] Browser tabs open: Projects board, branch protection settings, Actions,
      PR #22, the latest CD run, the live app.
- [ ] Close notifications, email and chat.
- [ ] `export APP_URL=$(terraform -chdir=terraform output -raw app_url)`

---

## Prompt 1: Project Foundation (F1), about 1 min
- **Board:** https://github.com/users/Hubert2c/projects/1. Issues #4–#27 with
  labels, milestones F1–F3, and the Todo / In Progress / Done columns.
- **Branch protection:** Settings → Branches → `main`. PR required, 7 status
  checks, up to date, conversation resolution, applies to admins, no force
  push or deletion.
- **Optional proof:** make a throwaway commit on local `main` and run
  `git push origin main`. It's rejected (protected branch). Afterwards, run
  `git reset --hard origin/main`.
- **Say:** why protection matters even when working solo.

## Prompt 2: Application Baseline (F1), about 1 min
```bash
python -m venv venv && source venv/Scripts/activate   # Windows Git Bash
pip install -r requirements-dev.txt
python run.py                                          # in-memory storage
curl localhost:5000/health
curl -X POST localhost:5000/groups -H "Content-Type: application/json" -d '{"name":"Demo"}'
```
- Show the README: section 4 (Run it locally) and the API table.

## Prompt 3: Containerization (F2), about 1.5 min
- Open the `Dockerfile`: pinned `python:3.12-slim`, security updates, non-root
  uid 10001, healthcheck, Gunicorn.
```bash
docker compose up --build -d
docker compose ps            # app "healthy", db "healthy"
curl localhost:5000/ready
docker compose down
```

## Prompt 4: CI Pipeline (F2), about 1.5 min
- Actions → **CI** → a green run: 7 jobs.
- **Failing run that caught a real problem:**
  - [PR #22](https://github.com/Hubert2c/Ikimina-tracker/pull/22): flake8
    F401, merge **blocked**, review comment, fix, green.
  - Stronger, because it's a real security problem:
    [run 44797135664](https://github.com/Hubert2c/Ikimina-tracker/actions/runs/44797135664).
    Trivy caught HIGH CVE-2026-85091 in zlib.

## Prompt 5: Infrastructure as Code, about 1.5 min
- In the IDE, walk through `terraform/`: `main.tf` (diagram comment),
  `network.tf`, `compute.tf`, `database.tf`, `registry.tf`, `variables.tf`,
  `outputs.tf`.
```bash
terraform -chdir=terraform plan      # "No changes" means the live infra matches the code
terraform -chdir=terraform output
```
- **Point out:** the private subnet and app VM with no public IP, the bastion,
  RDS PostgreSQL with public access off, ECR, the 3 security groups, and
  the bastion's double role as NAT for the private subnet.

## Prompt 6: Configuration Management, about 1.5 min
- Show `ansible/playbook.yml` (2 plays), `inventory/hosts.ini.example`
  (ProxyJump), and `templates/`.
- **Show a run:** the latest CD run → "Run the Ansible playbook" step
  (PLAY RECAP: `failed=0`).
- **The task that matters most:** "Log in to the private container registry
  (ECR)" plus pull plus `docker compose up -d`. Without it the VM can't get
  the new image. (Or the nginx reverse proxy on the bastion, which is what
  makes it reachable at all.)

## Prompt 7: Security Scanning, about 1.5 min
- Actions → a CI run → **Security scan (container image)** and **Security scan
  (IaC)** logs.
- **One real finding:** CVE-2026-85091. Show the failed run, the Dockerfile
  fix (`apt-get upgrade`), and the green rerun.
- Show the `SECURITY.md` findings log and the accepted risks (e.g.
  `CKV_AWS_260`, HTTP with no domain yet, and its `checkov:skip` comment).

## Prompt 8: Full Pipeline and Deployment, about 2 min
- Merge the prepared PR, then Actions → **CD** opens automatically.
- **Walk through:** CI checks (7 jobs) → Build, scan and push to ECR → Deploy
  (AWS OIDC login, temporary security group rule, Ansible, smoke test, rule
  removed).
- While it runs, open the AWS console: ECR → Repositories →
  `ikimina-tracker`. The new SHA tag appears.
- **When it's green, use the app** (not just `/health`):
```bash
curl $APP_URL/version            # equals the merged commit SHA
curl -X POST $APP_URL/groups -H "Content-Type: application/json" -d '{"name":"Live demo"}'
curl -X POST $APP_URL/groups/1/members -H "Content-Type: application/json" -d '{"member":"Aline"}'
curl -X POST $APP_URL/groups/1/contributions -H "Content-Type: application/json" -d '{"member":"Aline","amount":5000}'
curl $APP_URL/groups/1
```

## Prompt 9: Observability, about 1 min
```bash
curl -i $APP_URL/health    # liveness: process up
curl -i $APP_URL/ready     # readiness: 200 = DB reachable, 503 = not
curl $APP_URL/version      # what's deployed
$(terraform -chdir=terraform output -raw ssh_app) sudo docker logs --tail 5 ikimina-app   # JSON request logs
```
- **Explain:** if `/health` is OK but `/ready` returns 503, the app is up but
  the database is down. That tells an operator where to look.

## Prompt 10: Reflection and Ownership, about 1.5 min
```bash
git log --oneline --graph --all | less     # F1 (Oct 23) → F2 (Oct 30) → F3 (Nov 7) → summative
```
Answer the three questions **in your own words**. Some honest points to think
about beforehand:
- **Most important design decision:** for example, keeping the app VM and the
  database private behind a single bastion. Or OIDC instead of stored AWS
  access keys. Or layering routes / services / storage from F1.
- **Weakest part today:** no HTTPS. Single VM (no redundancy or zero-downtime
  deploy). Local Terraform state. Solo reviews.
- **Fix first before going live:** TLS with a domain, then remote Terraform
  state, then a second app VM behind a load balancer, monitoring and alerts.
