# Branch Protection Rules for `main`

Settings → Branches → Add branch ruleset / protection rule → pattern `main`.

| Setting | Why it matters |
|---------|----------------|
| Require a pull request before merging | No direct pushes; every change is visible and reviewable |
| Require approvals (1) | A second person catches bugs and shares knowledge |
| Dismiss stale approvals on new commits | An approval can't be reused for code the reviewer never saw |
| Require status checks to pass: `Lint (flake8)`, `Test (pytest)`, `Docker build` | Code that fails linting, tests or the Docker build can't merge |
| Require branches to be up to date | Prevents merging code tested against an outdated main |
| Require conversation resolution | Review feedback can't be silently ignored |
| Include administrators | Rules apply to everyone, including the repo owner |

## Adding the CI checks (Formative 2)
GitHub only lists a status check after it has run at least once, so:
1. Push any branch so the CI workflow runs once.
2. Settings → Branches → edit the `main` rule → tick **Require status checks
   to pass before merging** and **Require branches to be up to date**.
3. In the search box add the three job names exactly as they appear in the
   Actions tab: `Lint (flake8)`, `Test (pytest)`, `Docker build`.
4. Save. Open a PR: the merge button stays disabled until all three are green.
