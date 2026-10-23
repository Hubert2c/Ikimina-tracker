# Branch Protection Rules for `main`

Settings → Branches → Add branch ruleset / protection rule → pattern `main`.

| Setting | Why it matters |
|---------|----------------|
| Require a pull request before merging | No direct pushes; every change is visible and reviewable |
| Require approvals (1) | A second person catches bugs and shares knowledge |
| Dismiss stale approvals on new commits | An approval can't be reused for code the reviewer never saw |
| Require status checks to pass | Broken code can't merge; CI checks are added in Formative 2 |
| Require branches to be up to date | Prevents merging code tested against an outdated main |
| Require conversation resolution | Review feedback can't be silently ignored |
| Include administrators | Rules apply to everyone, including the repo owner |

Note: GitHub only lists a status check after it has run once, so the
"required checks" box will be completed in Formative 2 when CI exists.
