# CI Evidence

This file records proof that the CI pipeline (`.github/workflows/ci.yml`) and
the branch protection on `main` actually block bad code.

## Failed run, then fixed

Pull request: `ci/pipeline-evidence` into `main`.

1. **Broken commit:** an unused import (`import os`) was added to
   `app/services.py` on purpose. flake8 reports `F401 'os' imported but unused`,
   so the **Lint (flake8)** job fails. **Docker build** never starts because it
   needs lint and tests to pass first. Branch protection keeps the merge button
   disabled.
2. **Fix commit:** the import was removed. All four required checks
   (Lint, Test, Docker build, Infrastructure validation) pass, so the PR can merge.

Run links are added below once both runs have finished.
