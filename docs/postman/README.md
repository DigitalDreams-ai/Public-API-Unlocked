# Postman – Unbounce Intake API

Postman collection and environments for testing the Unbounce Intake API (`POST /v1/unbounce/intakes`). Layout and conventions follow the **Shulman API** Postman assets in `stash/force-app/main/default/docs/postman` (e.g. `Shulman API.postman_collection.json`, `Referral API Environment (Staging).postman_environment.json`).

## Files

| File | Purpose |
|------|---------|
| `Unbounce Intake API.postman_collection.json` | Requests and test scripts for the Unbounce intake endpoint. |
| `Unbounce Intake API Environment (Dev Scratch Org).postman_environment.json` | Dev scratch-org Experience Cloud base URL and `rest_path`: `services/apexrest`. |
| `Unbounce Intake API Environment (Beta).postman_environment.json` | Beta Experience Cloud base URL and `rest_path`: `services/apexrest`. |
| `Unbounce Intake API Environment (Production).postman_environment.json` | Production Experience Cloud base URL placeholder and `rest_path`: `services/apexrest`. |

## Import

1. Postman → **Import** → select the collection and one or more environment files above.
2. Choose the imported environment in the environment dropdown.

## Environment variables

- **base_url** – Site base URL. Include any site path prefix such as `/api` when the site uses one.
- **rest_path** – `services/apexrest` for all environments. Pre-set in each environment.
- **api_key** – Required. Sent as the `X-Api-Key` header and must match exactly one active **Unbounce Integration Config** record.
- **webhook_secret** – Optional; only if you use Unbounce webhook signature verification.
- **intake_id** – Set by the collection when a create request returns 201.

The API is public and uses **X-Api-Key** only (no session or OAuth). Set **api_key** in your Postman environment to match the specific active **Unbounce Integration Config** record you want to route through.

Current environment defaults:

- **Dev Scratch Org**: `https://drive-saas-1388-dev-ed.scratch.my.salesforce-sites.com`
- **Beta**: `https://shulman-hill--beta.sandbox.my.salesforce-sites.com/api`
- **Production**: placeholder only; replace with the live production site URL before use

## Requests

| Request | Purpose |
|--------|---------|
| **Create Intake** | Flat payload (first_name, last_name, email, etc.); asserts 201 and `intakeId`. |
| **Create Intake (with data wrapper)** | Payload with a `data` object. |
| **Create Intake (with signature)** | Optional `x-unbounce-signature` header. |
| **Create Intake – Invalid JSON** | Expects 400 and `errorMessage`. |

## Prerequisites

- At least one active **Unbounce Integration Config** record with a unique **API Key**.
- If you also use outbound status updates, saving **Outbound Webhook URL** auto-provisions a Remote Site Setting for that webhook domain.
- For Experience Cloud: **Unbounce Intake API (Guest)** permission set assigned to the site guest profile.
- For Beta and Production, keep `/api` in **base_url** if the site path prefix is `api`.

## Reference: Shulman API Postman

The over‑engineered Shulman API in `stash/force-app/main/default/docs/postman` provides:

- **Shulman API.postman_collection.json** – Referrals, Intakes, Webhooks, OAuth token, validation examples.
- **Referral API Environment (Staging | Production)** – `base_url`, OAuth `client_id`/`client_secret`, `partner_api_key`, `access_token`, etc.

Unbounce Intake API is a single-endpoint, public API using X-Api-Key only; the Unbounce collection mirrors the same folder layout, test script style, and environment variable usage as the Shulman collection.
