# Branch Protection Rules for `main`

Settings → Branches → Add branch ruleset / protection rule → pattern `main`.

| Setting | Why it matters |
|---------|----------------|
| Require a pull request before merging | No direct pushes; every change is visible and reviewable |
| Require approvals: **0** | Solo project: GitHub does not let an author approve their own PR, so 1 approval would block every merge. The PR plus required CI checks is the gate. Raise to 1 if a collaborator joins |
| Require status checks to pass: `Lint (flake8)`, `Test (pytest)`, `Docker build`, `Infrastructure validation`, `Security scan (dependencies)`, `Security scan (container image)`, `Security scan (IaC)` | Code that fails linting, tests, Docker validation, infrastructure validation or any security scan can't merge |
| Require branches to be up to date | Prevents merging code tested against an outdated main |
| Require conversation resolution | Review feedback can't be silently ignored |
| Include administrators | Rules apply to everyone, including the repo owner |

## Adding the CI checks (Formative 2)
GitHub only lists a status check after it has run at least once, so:
1. Push any branch so the CI workflow runs once.
2. Settings → Branches → edit the `main` rule → tick **Require status checks
   to pass before merging** and **Require branches to be up to date**.
3. In the search box add the seven job names exactly as they appear in the
   Actions tab: `Lint (flake8)`, `Test (pytest)`, `Docker build`,
   `Infrastructure validation`, `Security scan (dependencies)`,
   `Security scan (container image)`, `Security scan (IaC)`.
4. Save. Open a PR: the merge button stays disabled until all seven are green.

Allow force pushes and Allow deletions are both **off**.
