# Ikimina Tracker

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
6. *(Planned)* USSD / SMS access, persistent database

## Technology Stack
- Python 3.10+, Flask (REST API)
- pytest (unit tests)
- *Planned:* Docker, GitHub Actions CI, cloud deployment

## Project Structure
```
app/
  __init__.py   # application factory
  routes.py     # HTTP layer only
  services.py   # business logic and validation
  storage.py    # data layer (in-memory; swappable for a database)
tests/          # unit tests
docs/           # planning, security and board documentation
run.py          # entry point
```
Routes, business logic and storage are separated so each can evolve into its
own service (e.g. a ledger service and a notification/USSD service).

## Running Locally
```bash
git clone <https://github.com/Hubert2c/Ikimina-tracker.git>
cd ikimina-tracker
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
python run.py                   # http://127.0.0.1:5000
```

### Run the tests
```bash
pytest
```

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
- Branch protection on `main` (see [docs/BRANCH_PROTECTION.md](docs/BRANCH_PROTECTION.md))
- All changes go through pull requests with review
- Project board: see [docs/PROJECT_BOARD.md](docs/PROJECT_BOARD.md)

MUNEZERO Hubert
