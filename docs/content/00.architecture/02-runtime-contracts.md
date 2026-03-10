# Runtime Contracts

## Inbound Submission Creation

- A request must match exactly one active `PublicApi_Integration_Config__c` by `API_Key__c`.
- Inbound mapping configuration is required (`Inbound_Payload_Configuration__c` must be populated).
- Inbound mapping configuration is validated before DML.
- Invalid or missing inbound mappings return HTTP `400`.

## Outbound Status Delivery

- Deliveries are attempted only when the configured outbound trigger field changes to an allowed value.
- Outbound mapping configuration is required and validated per delivery item.
- Invalid mapping config does not crash the queueable batch; delivery is recorded as `Failed`.
- Empty mapped payloads are treated as configuration failures and recorded as `Failed`.
- Remote Site Setting provisioning is explicit.
- Admins provision the webhook domain from the Request Builder controller before outbound delivery is allowed.
- If the configured webhook domain is not provisioned, delivery fails fast with a configuration error.

## Mapping Token Format

- Only `$intakes.<FieldApiName>` is accepted.
- Legacy prefixes and raw field names are rejected by validation.
