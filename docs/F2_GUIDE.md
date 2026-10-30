# Formative 2 - Step-by-step plan for the GitHub evidence

The code is ready; these steps produce the evidence the rubric asks for
(3+ green runs, 1 red-then-fixed run, a reviewed PR, branch protection).
Each step is one branch -> one pull request -> review -> merge.

## 0. Before you start
- Docker Desktop installed; `docker compose up --build` works on your machine.
- Create issues #11-#17 from `docs/PROJECT_BOARD.md` and put them on the board.
  Move each card to *In Progress* when you start it and *Done* when its PR merges.

## 1. PR 1 - `feature/postgres-storage` (closes #11, #15)
Files: `app/storage.py`, `app/services.py`, `app/__init__.py`, `run.py`,
`tests/conftest.py`, `tests/test_api.py`, `pytest.ini`, `requirements*.txt`, `.flake8`
```bash
git checkout main && git pull
git checkout -b feature/postgres-storage
git add app run.py tests pytest.ini requirements.txt requirements-dev.txt .flake8
git commit -m "Add PostgreSQL store and run tests on both backends"
git push -u origin feature/postgres-storage
```
No CI yet on this branch, that's fine. Open the PR, get a review, merge.

## 2. PR 2 - `devops/docker` (closes #13, #14)
Files: `Dockerfile`, `.dockerignore`, `docker-compose.yml`, `.env.example`
```bash
git checkout main && git pull && git checkout -b devops/docker
git add Dockerfile .dockerignore docker-compose.yml .env.example
git commit -m "Containerize app and add compose stack with PostgreSQL"
git push -u origin devops/docker
```
Screenshot `docker compose ps` showing both containers *healthy* for your notes.

## 3. PR 3 - `devops/ci-pipeline` (closes #12)  -> green run #1
```bash
git checkout main && git pull && git checkout -b devops/ci-pipeline
git add .github/workflows/ci.yml
git commit -m "Add CI pipeline: lint, test, docker build"
git push -u origin devops/ci-pipeline
```
Open the Actions tab: all three jobs should go green. Merge the PR.

## 4. Turn on required checks (closes #16)
Follow `docs/BRANCH_PROTECTION.md` -> "Adding the CI checks".

## 5. PR 4 - the deliberate failure, then the fix  -> red run, then green run #2
```bash
git checkout main && git pull && git checkout -b test/ci-catches-bugs
```
Break something on purpose, e.g. in `app/services.py` change
`amount <= 0` to `amount < 0` (zero would be accepted).
```bash
git commit -am "Allow zero contributions"
git push -u origin test/ci-catches-bugs
```
Open the PR. **Test (pytest)** turns red (`test_rejects_bad_amounts` fails)
and the merge button is blocked. Screenshot it. Have your reviewer leave a
comment on the failing line. Then revert the change:
```bash
git commit -am "Fix: reject zero contributions (caught by CI)"
git push
```
CI goes green; reviewer approves; merge. (You can also break linting instead,
e.g. add an unused `import os`, to show the **Lint** job failing.)

## 6. PR 5 - `docs/f2-readme` (closes #17)  -> green run #3
```bash
git checkout main && git pull && git checkout -b docs/f2-readme
git add README.md docs/
git commit -m "Document Docker Compose and CI"
git push -u origin docs/f2-readme
```
Replace `<YOUR-GITHUB-USERNAME>` in the README badge first. Merge after review.

## 7. Tag the submission
```bash
git checkout main && git pull
git tag -a formative-2-submission -m "Formative 2: Docker + CI"
git push origin formative-2-submission
git rev-parse HEAD      # the commit SHA to paste on Canvas
```

## Evidence checklist
- [ ] 3+ green runs in the Actions tab
- [ ] 1 red run followed by a green fix (PR 4)
- [ ] PR(s) with CI status and reviewer comments/approval
- [ ] Commits from more than one team member
- [ ] `main` rule shows the 3 required checks
- [ ] Project board cards moved to Done
- [ ] Tag pushed; SHA/tag + repo URL + progress report on Canvas
