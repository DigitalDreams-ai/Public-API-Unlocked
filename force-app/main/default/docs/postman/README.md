# Postman – Unbounce Intake API

Postman collection and environments for testing the Unbounce Intake API (`POST /v1/unbounce/intakes`). Layout and conventions follow the **Shulman API** Postman assets in `stash/force-app/main/default/docs/postman` (e.g. `Shulman API.postman_collection.json`, `Referral API Environment (Staging).postman_environment.json`).

## Files

| File | Purpose |
|------|---------|
| `Unbounce Intake API.postman_collection.json` | Requests and test scripts for the Unbounce intake endpoint. |
| `Unbounce Intake API Environment (Dev).postman_environment.json` | Dev org base URL and `rest_path`: `services/apexrest`. |
| `Unbounce Intake API Environment (Experience Cloud).postman_environment.json` | Experience Cloud site base URL and `rest_path`: `apexrest`. |

## Import

1. Postman → **Import** → select the collection and one environment file above.
2. Choose the imported environment in the environment dropdown.

## Environment variables

- **base_url** – Org URL (Dev) or site URL (Experience Cloud). Set to your org/site; leave placeholders only for reference.
- **rest_path** – `services/apexrest` (Dev) or `apexrest` (Experience Cloud). Pre-set in each environment.
- **webhook_secret** – Optional; only if you use Unbounce webhook signature verification.
- **intake_id** – Set by the collection when a create request returns 201.

## Requests

| Request | Purpose |
|--------|---------|
| **Create Intake** | Flat payload (first_name, last_name, email, etc.); asserts 201 and `intakeId`. |
| **Create Intake (with data wrapper)** | Payload with a `data` object. |
| **Create Intake (with signature)** | Optional `x-unbounce-signature` header. |
| **Create Intake – Invalid JSON** | Expects 400 and `errorMessage`. |

## Prerequisites

- **Unbounce Config** org default: at least **Default Firm Id** (Setup → Custom Settings → Unbounce Config → Manage).
- For Experience Cloud: **Unbounce Intake API (Guest)** permission set assigned to the site guest profile.

## Reference: Shulman API Postman

The over‑engineered Shulman API in `stash/force-app/main/default/docs/postman` provides:

- **Shulman API.postman_collection.json** – Referrals, Intakes, Webhooks, OAuth token, validation examples.
- **Referral API Environment (Staging | Production)** – `base_url`, OAuth `client_id`/`client_secret`, `partner_api_key`, `access_token`, etc.

Unbounce Intake API is a single-endpoint, no-OAuth flow; the Unbounce collection mirrors the same folder layout, test script style, and environment variable usage as the Shulman collection.
