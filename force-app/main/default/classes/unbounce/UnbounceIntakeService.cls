/**
 * Service class for creating intakes from Unbounce webhook submissions.
 */
public with sharing class UnbounceIntakeService {

    /**
     * Creates an intake from Unbounce webhook payload.
     *
     * @param payload Unbounce webhook JSON as Map
     * @param firmId Optional firm to associate (from config)
     * @param caseTypeName Optional case type name (from config or payload)
     * @param referredByPartyName Optional Party name for Referred_By__c (e.g. PMAX-Unbounce); looked up by Name
     * @return Created intake record
     */
    public static litify_pm__Intake__c createIntakeFromUnbounce(
        Map<String, Object> payload,
        Id firmId,
        String caseTypeName,
        String referredByPartyName
    ) {
        if (payload == null) {
            throw new UnbounceIntakeServiceException('Payload cannot be null');
        }

        Map<String, Object> mappedPayload = UnbounceCustomMappingService.applyMapping(payload);
        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(mappedPayload);

        Id referredByPartyId = resolveReferredByPartyId(referredByPartyName);
        if (referredByPartyId != null) {
            intake.Referred_By__c = referredByPartyId;
        }

        // Case type lookup if provided
        if (String.isNotBlank(caseTypeName)) {
            Id caseTypeId = resolveCaseTypeId(caseTypeName);
            if (caseTypeId != null) {
                intake.litify_pm__Case_Type__c = caseTypeId;
            }
        }

        // Default status for new leads
        if (String.isBlank(intake.litify_pm__Status__c)) {
            intake.litify_pm__Status__c = 'Lead Generated';
        }

        try {
            insert intake;
            return intake;
        } catch (DmlException e) {
            throw new UnbounceIntakeServiceException('Failed to create intake: ' + e.getMessage());
        }
    }

    private static Id resolveCaseTypeId(String caseTypeName) {
        try {
            List<litify_pm__Case_Type__c> caseTypes = [
                SELECT Id
                FROM litify_pm__Case_Type__c
                WHERE Name = :caseTypeName
                LIMIT 1
            ];
            return caseTypes.isEmpty() ? null : caseTypes[0].Id;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Resolves Referred_By__c lookup: finds Party record by Name (no hardcoded Ids).
     * Uses the SObject type that Referred_By__c references (e.g. Account). Intake has Referred_By__c only (no namespaced variant).
     */
    private static Id resolveReferredByPartyId(String partyName) {
        if (String.isBlank(partyName)) {
            return null;
        }
        try {
            Schema.SObjectType intakeType = litify_pm__Intake__c.SObjectType;
            Schema.SObjectField field = intakeType.getDescribe().fields.getMap().get('Referred_By__c');
            if (field == null) {
                return null;
            }
            List<Schema.SObjectType> refTypes = field.getDescribe().getReferenceTo();
            if (refTypes.isEmpty()) {
                return null;
            }
            Schema.SObjectType refType = refTypes[0];
            String objectName = refType.getDescribe().getName();
            String query = 'SELECT Id FROM ' + objectName + ' WHERE Name = :partyName LIMIT 1';
            List<SObject> found = Database.query(query);
            return found.isEmpty() ? null : (Id) found[0].get('Id');
        } catch (Exception e) {
            return null;
        }
    }
}
