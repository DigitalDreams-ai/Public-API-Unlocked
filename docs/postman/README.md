# Postman – Public API Submissions

Postman collection and environments for testing the public guest API (`POST /v1/publicapi/submissions`). Layout and conventions follow the **Shulman API** Postman assets in `stash/force-app/main/default/docs/postman` (e.g. `Shulman API.postman_collection.json`, `Referral API Environment (Staging).postman_environment.json`).

For complete endpoint and webhook documentation, see [docs/content](../content/README.md).

## Files

| File | Purpose |
|------|---------|
| `PublicApi Intake API.postman_collection.json` | Requests and test scripts for the public submissions endpoint. |
| `PublicApi Intake API Environment (Dev Scratch Org).postman_environment.json` | Dev scratch-org Experience Cloud base URL and `rest_path`: `services/apexrest`. |
| `PublicApi Intake API Environment (Beta).postman_environment.json` | Beta Experience Cloud base URL and `rest_path`: `services/apexrest`. |
| `PublicApi Intake API Environment (Production).postman_environment.json` | Production Experience Cloud base URL and `rest_path`: `services/apexrest`. |

## Import

1. Postman → **Import** → select the collection and one or more environment files above.
2. Choose the imported environment in the environment dropdown.

## Environment variables

- **base_url** – Site base URL. Include any site path prefix such as `/api` when the site uses one.
- **rest_path** – `services/apexrest` for all environments. Pre-set in each environment.
- **api_key** – Required. Sent as the `X-Api-Key` header and must match exactly one active **Public API Integration Config** record.
- **webhook_secret** – Optional; only if you use webhook signature verification.
- **record_id** – Set by the collection when a create request returns 201.

The API is public and uses **X-Api-Key** only (no session or OAuth). Set **api_key** in your Postman environment to match the specific active **Public API Integration Config** record you want to route through.

Current environment defaults:

- **Dev Scratch Org**: `https://drive-saas-1388-dev-ed.scratch.my.salesforce-sites.com`
- **Beta**: `https://shulman-hill--beta.sandbox.my.salesforce-sites.com/api`
- **Production**: placeholder only; replace with the live production site URL before use

## Requests

| Request | Purpose |
|--------|---------|
| **Create Submission** | Flat payload (first_name, last_name, email, etc.); asserts 201 and `recordId`. |
| **Create Submission (with data wrapper)** | Payload with a `data` object. |
| **Create Submission (with signature)** | Optional `x-publicapi-signature` header. |
| **Create Submission – Invalid JSON** | Expects 400 and `errorMessage`. |

## Prerequisites

- At least one active **Public API Integration Config** record with a unique **API Key**.
- If you also use outbound status updates, provision the webhook domain explicitly from the Request Builder before testing deliveries.
- For Experience Cloud: **Public API Guest Access** permission set assigned to the site guest profile.
- For Beta and Production, keep `/api` in **base_url** if the site path prefix is `api`.

## Reference: Shulman API Postman

The over‑engineered Shulman API in `stash/force-app/main/default/docs/postman` provides:

- **Shulman API.postman_collection.json** – Referrals, Intakes, Webhooks, OAuth token, validation examples.
- **Referral API Environment (Staging | Production)** – `base_url`, OAuth `client_id`/`client_secret`, `partner_api_key`, `access_token`, etc.

Public API submissions is a single-endpoint, public API using X-Api-Key only; the collection mirrors the same folder layout, test script style, and environment variable usage as the Shulman collection.
