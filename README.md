# Standard-Unlocked-Shulman Template

This template repository contains everything you need to realize enterprise-grade Salesforce CICD practices without making an enterprise-grade investment. 

The included [Github Actions](.github/workflows) provide a standardized (and mostly automated!) framework for building, testing, and delivering solutions in a consistent and repeatable manner. 

We strongly advocate adhering to a "Release Train" development methodology for Salesforce development. When applied with discipline, this approach consistently balances business demands, development rigor, and the unique constraints of working with Salesforce metadata significantly better than other popular methodologies (Scrum 👀).

## Salesforce Release Train Development Cadence

![image](https://github.com/user-attachments/assets/6b7d1dc8-30cb-4740-964e-8cd55f54a847)
[Image Credit: CumulusCI Documentation](https://cumulusci.readthedocs.io/en/stable/cumulusci-flow.html)

## Getting Started

1. Create a _new_ Repository in your organization using this repository as the `Repository Template`
2. Run the setup script locally to replace project tokens:
   ```bash
   python scripts/setup_new_project.py
   ```
   Or with explicit repository name:
   ```bash
   python scripts/setup_new_project.py --repo-name "Your-Project-Name" --non-interactive
   ```
   
   The script will:
   - Read project values from `cumulusci.yml` (or derive from repository name)
   - Permanently replace `__PROJECT_NAME__` and `__PROJECT_LABEL__` tokens in all filenames and file contents
   - Rename directories (e.g., `robot/__PROJECT_LABEL__/` → `robot/Your-Project-Name/`)
   - Update all configuration files (`.gitignore`, `sfdx-project.json`, `orgs/*.json`, etc.)
   
   Then commit the changes:
   ```bash
   git add .
   git commit -m "Replace project tokens with actual project name"
   git push
   ```
3. Follow the [`Initial Setup` instructions](https://github.com/DigitalDreams-ai/Standard-Unlocked-Shulman/tree/main/.github/workflows/README.md#initial-setup) to configure the included CICD for this project.

> [!IMPORTANT]
> **Template Protection**: This repository is protected by multiple safeguards to ensure it is NEVER modified when used as a template. See [TEMPLATE_PROTECTION.md](TEMPLATE_PROTECTION.md) for details.

> [!NOTE]
> As you explore this project, you may notice a large number of tokens such as `__PROJECT_LABEL__` and `__PROJECT_NAME__`. These correspond to the `name_managed` and `name` attributes in [cumulusci.yml](cumulusci.yml). **Run `scripts/setup_new_project.py` once at project initialization** to permanently replace these tokens. After that, all files will use your actual project name.

## Development

1. [Set up CumulusCI](https://cumulusci.readthedocs.io/en/latest/tutorial.html) in your preferred development environnment.
2. **Set a default Dev Hub** (required for scratch orgs). Use a Production or Developer Edition org with [Dev Hub enabled](https://help.salesforce.com/s/articleView?id=sf.devhub_enable.htm):
   - **First-time:** `sf org login web --alias mydevhub --set-default-dev-hub`
   - **Already authorized:** `sf config set target-dev-hub <your-dev-hub-alias>`
3. Run `cci flow run dev_org --org dev` to deploy this project.
4. Run `cci org browser dev` to open the org in your browser.
5. Build your solution, periodically run `cci task run retrieve_changes --org dev`, and commit your changes to a `feature/**` branch using your preferred git tooling.
6. When you're ready, run `git push` to send your changes to GitHub.
7. Submit a PR.
8. Monitor for Success/Failure

To test the Public API Intake API in dev via Experience Cloud (guest, no session), see [Experience Cloud site setup for API testing](docs/experience-site-dev-setup.md).

----

## Releases

### [Recommended] Release this project using the Built-in CICD Actions

Follow the provided [`Release` instructions](https://github.com/DigitalDreams-ai/Standard-Unlocked-Shulman/blob/main/.github/workflows/README.md#releases).


---

### [Advanced] Release this project using your CLI

#### To release a new `beta` version of this package:

1. Run `git checkout main` to switch to the main branch.
2. Run `git pull` to download the latest changes from Github.
3. Run `cci flow run dependencies --org dev` to prepare a scratch org for the process of packaging.
4. Run `cci flow run release_unlocked_beta --org dev` to release a new beta version of this package.
5. [Optional] Run `cci org browser dev` to open the org in your browser.

#### To release a new `production` version of this package:

1. Run `git checkout main` to switch to the main branch.
2. Run `git pull` to download the latest changes from Github.
3. Run `cci flow run release_unlocked_production --org dev --debug` to release a new beta version of this package.
4. Run `cci org browser dev` to open the org in your browser.
5. [OPTIONAL] Run `cci flow run install_prod --org <target-org-alias>` to install the package and _all of its dependencies_ in `<target-org-alias>`.


=====================================
