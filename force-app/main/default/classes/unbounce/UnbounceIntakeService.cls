/**
 * Service class for creating intakes from Unbounce webhook submissions.
 */
public with sharing class UnbounceIntakeService {

    /**
     * Creates an intake from Unbounce webhook payload.
     *
     * @param payload Unbounce webhook JSON as Map
     * @param firmId Optional firm to associate (from config)
     * @param caseTypeName Optional default case type name from config (used only when payload does not send caseType)
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

        // Client lookup: use email to find or create an Account and set the Intake Client lookup.
        Id clientAccountId = resolveClientAccountId(intake);
        if (clientAccountId != null) {
            intake.litify_pm__Client__c = clientAccountId;
        }

        Id referredByPartyId = resolveReferredByPartyId(referredByPartyName);
        if (referredByPartyId != null) {
            intake.Referred_By__c = referredByPartyId;
        }

        // Case Type lookup by Name:
        // 1) Prefer payload key 'caseType' or 'casetype' (after custom mapping).
        // 2) Fall back to caseTypeName from config when payload does not send either.
        String caseTypeFromPayload = (String) mappedPayload.get('caseType');
        if (String.isBlank(caseTypeFromPayload)) {
            caseTypeFromPayload = (String) mappedPayload.get('casetype');
        }
        if (String.isBlank(caseTypeFromPayload) && mappedPayload.containsKey('data') && mappedPayload.get('data') instanceof Map<String, Object>) {
            Map<String, Object> dataMap = (Map<String, Object>) mappedPayload.get('data');
            caseTypeFromPayload = (String) dataMap.get('caseType');
            if (String.isBlank(caseTypeFromPayload)) {
                caseTypeFromPayload = (String) dataMap.get('casetype');
            }
        }
        String effectiveCaseTypeName = String.isNotBlank(caseTypeFromPayload)
            ? caseTypeFromPayload
            : caseTypeName;
        if (String.isNotBlank(effectiveCaseTypeName)) {
            Id caseTypeId = resolveCaseTypeId(effectiveCaseTypeName);
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

    /**
     * Resolves the Intake Client lookup (litify_pm__Client__c) using email:
     * - If an Account with matching email exists, returns its Id.
     * - Otherwise, creates a new Account using Intake contact fields:
     *   - Type = 'Potential Client'
     *   - Record Type = 'Individual' (by DeveloperName or Name), when available
     */
    private static Id resolveClientAccountId(litify_pm__Intake__c intake) {
        String email = (String) intake.get('litify_pm__Email__c');
        if (String.isBlank(email)) {
            return null;
        }

        Id existing = findAccountByEmail(email);
        if (existing != null) {
            return existing;
        }

        return createClientAccountFromIntake(intake, email);
    }

    private static Id findAccountByEmail(String email) {
        try {
            Schema.DescribeSObjectResult dr = Account.SObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = dr.fields.getMap();

            // Prefer Litify email field when present
            Boolean hasLitifyEmail = fieldMap.containsKey('litify_pm__Email__c');
            Boolean hasPersonEmail = fieldMap.containsKey('PersonEmail');
            Boolean hasEmail = fieldMap.containsKey('Email');

            List<String> conditions = new List<String>();
            if (hasLitifyEmail) {
                conditions.add('litify_pm__Email__c = :email');
            } else {
                if (hasPersonEmail) {
                    conditions.add('PersonEmail = :email');
                }
                if (hasEmail) {
                    conditions.add('Email = :email');
                }
            }
            if (conditions.isEmpty()) {
                return null;
            }

            String soql = 'SELECT Id FROM Account WHERE ' + String.join(conditions, ' OR ') + ' LIMIT 1';
            List<Account> results = Database.query(soql);
            return results.isEmpty() ? null : results[0].Id;
        } catch (Exception e) {
            return null;
        }
    }

    private static Id createClientAccountFromIntake(litify_pm__Intake__c intake, String email) {
        try {
            Schema.DescribeSObjectResult dr = Account.SObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = dr.fields.getMap();

            Account a = new Account();

            // Record Type = 'Individual' (by DeveloperName or Name), when available
            Id individualRtId = getIndividualAccountRecordTypeId();
            if (individualRtId != null) {
                a.RecordTypeId = individualRtId;
            }

            // Type = 'Potential Client'
            if (fieldMap.containsKey('Type')) {
                try {
                    a.put('Type', 'Potential Client');
                } catch (Exception e) {
                    // If Type is restricted and value not allowed, let DML surface error rather than fail silently
                }
            }

            String firstName = (String) intake.get('litify_pm__First_Name__c');
            String lastName = (String) intake.get('litify_pm__Last_Name__c');

            if (fieldMap.containsKey('FirstName') && String.isNotBlank(firstName)) {
                a.put('FirstName', firstName);
            }
            if (fieldMap.containsKey('LastName') && String.isNotBlank(lastName)) {
                a.put('LastName', lastName);
            }

            // Email mapped to litify_pm__Email__c when available
            if (fieldMap.containsKey('litify_pm__Email__c')) {
                a.put('litify_pm__Email__c', email);
            } else if (fieldMap.containsKey('PersonEmail')) {
                a.put('PersonEmail', email);
            } else if (fieldMap.containsKey('Email')) {
                a.put('Email', email);
            }

            // Phone mapped to litify_pm__Phone_Mobile__c when available
            String mobilePhone = null;
            if (Account.SObjectType.getDescribe().fields.getMap().containsKey('litify_pm__Phone_Mobile__c')) {
                String intakeMobile = (String) intake.get('litify_pm__Phone_Mobile__c');
                String intakePhone = (String) intake.get('litify_pm__Phone__c');
                mobilePhone = String.isNotBlank(intakeMobile) ? intakeMobile : intakePhone;
                if (String.isNotBlank(mobilePhone)) {
                    a.put('litify_pm__Phone_Mobile__c', mobilePhone);
                }
            }

            // Fallback Name when needed (Person accounts may use FirstName/LastName; standard Account needs Name)
            if (String.isBlank((String) a.get('Name'))) {
                List<String> parts = new List<String>();
                if (String.isNotBlank(firstName)) parts.add(firstName);
                if (String.isNotBlank(lastName)) parts.add(lastName);
                String name = String.join(parts, ' ');
                if (String.isBlank(name)) {
                    name = email;
                }
                a.Name = name;
            }

            insert a;
            return a.Id;
        } catch (DmlException e) {
            throw new UnbounceIntakeServiceException('Failed to create client Account: ' + e.getMessage());
        } catch (Exception e) {
            return null;
        }
    }

    private static Id individualAccountRecordTypeId;

    private static Id getIndividualAccountRecordTypeId() {
        if (individualAccountRecordTypeId != null) {
            return individualAccountRecordTypeId;
        }
        try {
            List<RecordType> rts = [
                SELECT Id, DeveloperName, Name
                FROM RecordType
                WHERE SObjectType = 'Account'
                AND (DeveloperName = 'Individual' OR Name = 'Individual')
                LIMIT 1
            ];
            if (!rts.isEmpty()) {
                individualAccountRecordTypeId = rts[0].Id;
            }
        } catch (Exception e) {
            // If not found, leave null; account will be created with default record type
        }
        return individualAccountRecordTypeId;
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
