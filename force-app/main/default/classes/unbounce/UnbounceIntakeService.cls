/**
 * Service class for creating intakes from Unbounce webhook submissions.
 */
public with sharing class UnbounceIntakeService {

    /**
     * Creates an intake from Unbounce webhook payload.
     *
     * @param payload Unbounce webhook JSON as Map
     * @param firmId Firm to associate (from config)
     * @param caseTypeName Optional case type name (from config or payload)
     * @return Created intake record
     */
    public static litify_pm__Intake__c createIntakeFromUnbounce(
        Map<String, Object> payload,
        Id firmId,
        String caseTypeName
    ) {
        if (payload == null) {
            throw new UnbounceIntakeServiceException('Payload cannot be null');
        }
        if (firmId == null) {
            throw new UnbounceIntakeServiceException('Firm ID is required');
        }

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        // Set firm ownership via Referred_By (Party) or Originating Firm
        // litify_pm__Intake__c uses Referred_By__c for standalone ownership
        Id firmPartyId = resolveFirmPartyId(firmId);
        if (firmPartyId != null) {
            intake.Referred_By__c = firmPartyId;
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

    private static Id resolveFirmPartyId(Id firmId) {
        try {
            List<litify_pm__Firm__c> firms = [
                SELECT Party__c
                FROM litify_pm__Firm__c
                WHERE Id = :firmId
                LIMIT 1
            ];
            return firms.isEmpty() ? null : firms[0].Party__c;
        } catch (Exception e) {
            return null;
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
}
