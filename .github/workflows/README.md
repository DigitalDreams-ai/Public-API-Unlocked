# Using these workflows

## Initial Setup
- [x] Navigate to Your Repository > Settings > Secrets and Actions > Actions
- [x] Create a new Repository Secret: `DEV_HUB_AUTH_URL`, and populate it with your Dev Hub's `sfdxAuthUrl` 
- [x] [Optional] Create a new Repository Secret: `BETA_ORG_AUTH_URL`, and populate it with your UAT Sandbox's `sfdxAuthUrl` 
- [x] [Optional] Create a new Repository Secret: `PROD_ORG_AUTH_URL`, and populate it with your Production Org's `sfdxAuthUrl` 

([How do I obtain an `sfdxAuthUrl`?](https://github.com/Nimba-Solutions/.github/wiki/Obtain-an-SFDX-Auth-URL))

### Postman publish (`publish-postman.yml`)

To sync the Public API Submissions collection and environments to Postman on push to `main` (or via **Run workflow**):

1. **Create a Postman API key**
   - Log in at [postman.com](https://www.postman.com) → **Settings** (profile) → **API Keys**.
   - **Generate API Key**; copy the key (you won’t see it again).

2. **Get your workspace ID**
   - In Postman, open the **Workspace** you want to publish to.
   - **Workspace Settings** → **Overview** → copy the **Workspace ID** from the URL or the settings page  
     (e.g. `https://go.postman.co/workspace/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx~yyyyyyyy` → the part after `workspace/` before `~` is often the workspace id, or use the **Share** dialog / API).

   To get it via API (with your API key):
   ```bash
   curl -s "https://api.getpostman.com/workspaces" \
     -H "X-Api-Key: YOUR_POSTMAN_API_KEY" | jq '.workspaces[] | {name, id}'
   ```
   Use the `id` of the workspace you want.

3. **Add repository secrets**
   - Repo → **Settings** → **Secrets and variables** → **Actions**.
   - **New repository secret**:
     - Name: `POSTMAN_API_KEY`  
       Value: your Postman API key from step 1.
   - **New repository secret**:
     - Name: `POSTMAN_WORKSPACE_ID`  
       Value: the workspace ID from step 2.

After that, the workflow will create or update the **Public API Submissions** collection and all three PublicApi environments (**Dev Scratch Org**, **Beta**, and **Production**) in that workspace when the corresponding files under `docs/postman/` change on `main`, or when you run the workflow manually.

## Releases

### [Recommended] Release this project using the Built-in CICD Actions

#### [Automatic] Generate Feature Test Packages & Beta Packages
1. [Contribute to this Project normally.](/README.md#development)
2. Confirm that the built-in GitHub Actions are running when Tasks are submitted for testing:
   -  `Test Feature (Unlocked)` should run when a `feature/**` Pull Request is opened, or subsequent commits are made.
   -  `Beta - Create (Unlocked)` should run when any Pull Request is merged into the `main` branch.

#### [Manual] Promote the Latest Beta Package
1. Navigate to Your Repository > Actions > `Beta - Promote (Unlocked)`.
2. Click `Run Workflow`.
3. Confirm.

#### [Manual] Install the Latest Promoted Package
1. Navigate to Your Repository > Actions > `Package - Install (Unlocked)`.
2. Click `Run Workflow`.
3. Select `Sandbox` or `Production`.
4. Confirm.

Note: Depending on the configuration of your GitHub Organization, you may need to specify some or all of the additional `GITHUB_TOKEN` permissions for these workflows to run successfully:

```yml
permissions:
  actions: write
  attestations: write
  checks: write
  contents: write
  deployments: write
  discussions: write
  issues: write
  packages: write
  pages: write
  pull-requests: write
  repository-projects: write
  security-events: write
  statuses: write
```
