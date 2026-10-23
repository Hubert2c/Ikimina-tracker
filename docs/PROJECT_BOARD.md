# Project Board (GitHub Projects, Kanban)

Columns: Backlog / In Progress / Done. Milestones: Formative 1, Formative 2.
Labels: feature, devops, security, testing, documentation.
All items assigned to the project owner. Create each as a GitHub Issue and add it to the board.

| # | Item | Label | Milestone | Column |
|---|------|-------|-----------|--------|
| 1 | As a treasurer, I want to create a savings group so that I can start tracking contributions | feature | F1 | Done |
| 2 | As a treasurer, I want to add members so that contributions are tied to real people | feature | F1 | Done |
| 3 | As a treasurer, I want to record contributions so that payments are never lost | feature | F1 | Done |
| 4 | As a member, I want to view my balance so that I can verify my savings | feature | F1 | Done |
| 5 | As a treasurer, I want input validation so that bad data is never stored | feature | F1 | Done |
| 6 | Write unit tests for the API | testing | F1 | Done |
| 7 | Write README and setup instructions | documentation | F1 | Done |
| 8 | Configure .gitignore, LICENSE and CODEOWNERS | security | F1 | Done |
| 9 | Enable branch protection on main | security | F1 | Done |
| 10 | As a member without a smartphone, I want USSD access so that I can check my balance | feature | F2 | Backlog |
| 11 | Replace in-memory storage with a database | feature | F2 | Backlog |
| 12 | Set up CI pipeline | devops | F2 | In Progress |
| 13 | Containerize the application | devops | F2 | Backlog |

## Acceptance criteria examples
**#3 Record contributions**
- [ ] Rejects unknown members, zero, negative and non-numeric amounts
- [ ] Contribution appears in the member's balance
- [ ] Covered by unit tests

**#9 Branch protection**
- [ ] All required settings enabled, including administrators
- [ ] Direct push to main is rejected
