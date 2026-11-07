# Security Policy - Ikimina Tracker

Ikimina Tracker stores savings-group balances, which are financial records,
so security is checked at every stage: in the code, in its dependencies, in the
container image and in the infrastructure code.

## Reporting a vulnerability
Please **do not** open a public issue. Use GitHub's
**Security -> Report a vulnerability** (private advisory) on this repository,
or contact the maintainers directly. We aim to reply within 7 days.

## Automated security scanning (CI)
These scans run on every pull request into `main` and must pass before merging.

| Scan | Tool | What it checks | Fails the pipeline when |
|------|------|----------------|-------------------------|
| Dependency scan | <!-- e.g. pip-audit --> | Known CVEs in Python packages | <!-- your rule --> |
| Container image scan | <!-- e.g. Trivy --> | OS + library CVEs inside the Docker image | <!-- e.g. HIGH/CRITICAL --> |
| IaC scan | <!-- e.g. Checkov / tfsec --> | Insecure Terraform settings | <!-- your rule --> |

<!-- Fill this table in once YOUR workflow is written, with the job names
     exactly as they appear in the Actions tab. -->

## Security measures in place
**Application**
- All input validated: names are text, 1-100 characters; amounts are finite,
  positive numbers up to 1,000,000,000.
- Request bodies limited to 16 KB (larger requests get `413`).
- Errors are always JSON; unexpected errors return a generic message and the
  details are only logged on the server.
- Security headers on every response: `X-Content-Type-Options`,
  `X-Frame-Options`, `Content-Security-Policy`, `Referrer-Policy`,
  `Cache-Control: no-store`.
- SQL uses parameterised queries only (no string-built SQL -> no SQL injection).
- Every fix is covered by a test in `tests/test_security.py`.

**Dependencies and container**
- All Python dependencies pinned to exact versions.
- Container runs as a non-root user (uid 10001); `.dockerignore` keeps `.env`,
  `.git` and tests out of the image.
- Database has no public port; it is only reachable from the app container.

**Repository**
- `.env` and secrets excluded by `.gitignore`; only `.env.example` is committed.
- `main` is protected: PR + 1 approval + passing CI required.

**Infrastructure** <!-- fill in from your Terraform and Ansible work -->
- <!-- e.g. security group allows only ports ... from ... -->
- <!-- e.g. SSH: key-only login, root login disabled -->
- <!-- e.g. host firewall (ufw) default deny incoming -->

## Findings log
Each finding: what was found, how, its severity, and what we did about it.

| # | Date | Found by | Finding | Severity | Status / fix |
|---|------|----------|---------|----------|--------------|
| 1 | 2026-11-07 | Manual testing | Contribution amounts of `NaN` or `Infinity` were accepted (Python's JSON parser allows them). One bad request turned every balance and the group total into `NaN` and made API responses invalid JSON. | High | **Fixed** - amounts must be finite (`math.isfinite`) and at most 1,000,000,000. Tests: `test_rejects_nan_and_infinity`, `test_rejects_amount_above_limit` |
| 2 | 2026-11-07 | Manual testing | No size limits: a 1 MB group name was stored, and request bodies were unlimited (memory / storage exhaustion). | Medium | **Fixed** - names limited to 100 characters, request bodies to 16 KB. Tests: `test_rejects_long_names`, `test_rejects_huge_request_body` |
| 3 | 2026-11-07 | Manual testing | Errors (404, 405, 500) returned Flask's HTML pages; an unexpected error could expose internal details. | Low | **Fixed** - JSON error handlers; generic 500 message. Tests: `test_errors_are_json`, `test_unexpected_error_hides_details` |
| 4 | 2026-11-07 | Manual testing | No HTTP security headers were sent. | Low | **Fixed** - headers added to every response. Test: `test_security_headers_on_every_response` |
| 5 | 2026-11-07 | pip-audit (local run) | Scanned `requirements-dev.txt`: **no known vulnerabilities**. | - | No action needed; re-checked on every PR by the dependency scan. |
| 6 | | <!-- your image scan --> | <!-- paste what it reports, e.g. CVEs in the base image --> | | <!-- fixed / accepted + why --> |
| 7 | | <!-- your IaC scan --> | <!-- e.g. "security group open to 0.0.0.0/0 on port 22" --> | | <!-- fixed / accepted + why --> |

### Accepted risks
<!-- Findings you decided NOT to fix, and why, e.g. a base-image CVE with no
     fix available yet, or a Checkov rule that doesn't apply to a student
     project (and the `skip` comment you added). Graders look for this. -->
