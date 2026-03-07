# ADR Summary: Public API Domain Architecture

## Status

Accepted

## Decision

Use domain-based organization under `classes/publicApi`:

- `api`
- `submission`
- `config`
- `mapping`
- `webhook`
- `ui`
- `testSupport`

Enforce runtime mapping contracts:

- Inbound and outbound mapping configs are required.
- Mapping tokens must use `$intakes.<FieldApiName>`.
- Invalid outbound config fails the delivery item and is logged; queueable batch continues.

## Why

- Aligns structure/patterns with Shulman-API.
- Improves reviewability and ownership boundaries.
- Makes runtime behavior deterministic and easier to operate in production.

## Consequences

- More explicit layering and cleaner orchestration boundaries.
- Slight increase in class count and indirection.
