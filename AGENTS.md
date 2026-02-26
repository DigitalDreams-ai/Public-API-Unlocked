# Repository Guidelines

## Project Structure & Module Organization
Core Salesforce metadata lives in `force-app/main/default/`:
- `classes/` (Apex services, controllers, models, tests)
- `triggers/` (trigger entry points)
- `objects/`, `flows/`, `permissionsets/`, `flexipages/`

Documentation is in `docs/` (`docs/content` for API docs, `docs/planning` for implementation notes).  
Automation config is in `cumulusci.yml`, `.github/workflows/`, and `scripts/`.

## Build, Test, and Development Commands
Use this sequence for daily development:
1. Create a feature branch: `git checkout -b feature/<name>`.
2. Prepare org and deploy baseline: `cci flow run dev_org --org dev`.
3. Optional org login: `cci org browser dev`.
4. Make changes in scratch org or repo.
5. If changes were made in org: `cci task run retrieve_changes --org dev`.
6. If changes were made in repo: `cci task run deploy --org dev --path force-app`.
7. Run dev tests: `cci task run run_tests --org dev`.
8. Deploy to UAT after dev tests pass: `cci task run deploy --org shulman-beta --path force-app`.
9. Run UAT tests: `cci task run run_tests --org shulman-beta`.

Useful targeted test command while iterating:
- `sf apex run test -n UnbounceUnlockedServiceTest -r human`

## Coding Style & Naming Conventions
- Use 4-space indentation in Apex and metadata.
- Apex naming: `PascalCase` classes, `camelCase` methods/variables.
- Keep code grouped by domain (`classes/intake`, `classes/referral`, `classes/webhook`).
- Follow bulk-safe patterns: no SOQL/DML in loops, service-layer orchestration, explicit exception classes.
- Avoid hardcoded org IDs; resolve record types/config by developer name.

## Testing Guidelines
- Place tests with their domain and use `@IsTest`.
- Cover happy path, failure path, and bulk behavior.
- Verify trigger + service integration, not just isolated methods.
- Keep org-wide Apex coverage above the configured `75%` gate.

## Commit & Pull Request Guidelines
- Commit with imperative subjects (for example: `Add intake status sync guard`).
- Push feature branch and open PR to the appropriate target branch.
- PR must include: summary, changed metadata paths, test evidence, and migration notes if needed.
- Wait for PR checks, fix failures, then merge.
- After merge, wait for **Beta - Create (Unlocked)**, run **Beta Promote (Unlocked)**, then use the installation link from the release.

## Security & Configuration Tips
- Never commit secrets, auth URLs, or API keys.
- Required GitHub secrets are documented in `.github/workflows/README.md` (`DEV_HUB_AUTH_URL`, optional `BETA_ORG_AUTH_URL`, `PROD_ORG_AUTH_URL`).
