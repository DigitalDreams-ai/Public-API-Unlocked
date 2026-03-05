# Runtime Contracts

## Inbound Submission Creation

- A request must match exactly one active `PublicApi_Integration_Config__c` by `API_Key__c`.
- Inbound mapping configuration is required (`Outbound_Payload_Configuration__c` must be populated).
- Inbound mapping configuration is validated before DML.
- Invalid or missing inbound mappings return HTTP `400`.

## Outbound Status Delivery

- Deliveries are attempted only for tracked submissions and allowed statuses.
- Outbound mapping configuration is required and validated per delivery item.
- Invalid mapping config does not crash the queueable batch; delivery is recorded as `Failed`.
- Empty mapped payloads are treated as configuration failures and recorded as `Failed`.

## Mapping Token Format

- Only `$intakes.<FieldApiName>` is accepted.
- Legacy prefixes and raw field names are rejected by validation.
