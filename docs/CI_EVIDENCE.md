# CI Evidence

This file records proof that the CI pipeline (`.github/workflows/ci.yml`) and
the branch protection on `main` actually block bad code.

## Failed run, then fixed

Pull request: [#22](https://github.com/Hubert2c/Ikimina-tracker/pull/22), `ci/pipeline-evidence` into `main`.

1. **Broken commit:** an unused import (`import os`) was added to
   `app/services.py` on purpose. flake8 reports `F401 'os' imported but unused`,
   so the **Lint (flake8)** job fails. **Docker build** never starts because it
   needs lint and tests to pass first. Branch protection keeps the merge button
   disabled.
2. **Fix commit:** the import was removed. All four required checks
   (Lint, Test, Docker build, Infrastructure validation) pass, so the PR can merge.

| Step | Run | Result |
|------|-----|--------|
| Broken commit | [run 44792077812](https://github.com/Hubert2c/Ikimina-tracker/actions/runs/44792077812) | ❌ `./app/services.py:4:1: F401 'os' imported but unused`; Docker build skipped; PR status **BLOCKED** |
| Code review | [review on PR #22](https://github.com/Hubert2c/Ikimina-tracker/pull/22#pullrequestreview-5997475231) | Line comment on the unused import, fix requested |
| Fix commit | see the PR's checks tab | ✅ all four required checks pass |

## Earlier successful runs (Formative 2)

- 4 green runs on the `f2` branch and [PR #1](https://github.com/Hubert2c/Ikimina-tracker/pull/1) on 2026-10-30.
