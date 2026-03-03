/**
 * Service class for creating intakes from Unbounce webhook submissions.
 */
public without sharing class UnbounceIntakeService {
    @TestVisible
    private static String forcedClientAccountCreateFailureMessage;

    /**
     * Creates an intake from Unbounce webhook payload.
     *
     * @param payload Unbounce webhook JSON as Map
     * @param referredByPartyName Optional Party name for Referred_By__c (e.g. PMAX-Unbounce); looked up by Name
     * @return Created intake record
     */
    public static litify_pm__Intake__c createIntakeFromUnbounce(
        Map<String, Object> payload,
        String referredByPartyName
    ) {
        UnbounceConfigService.Config config = new UnbounceConfigService.Config();
        config.referredByPartyName = referredByPartyName;
        return createIntakeFromUnbounce(payload, config);
    }

    public static litify_pm__Intake__c createIntakeFromUnbounce(
        Map<String, Object> payload,
        UnbounceConfigService.Config config
    ) {
        if (payload == null) {
            throw new UnbounceIntakeServiceException('Payload cannot be null');
        }

        Map<String, Object> mappedPayload = UnbounceCustomMappingService.applyMapping(payload);
        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(mappedPayload);
        setBooleanFieldIfExists(intake, 'Created_By_Unbounce_API__c', true);
        if (config != null && config.id != null) {
            setFieldIfExists(intake, 'Unbounce_Integration_Config_Id__c', String.valueOf(config.id));
        }

        // Client lookup: use email to find or create an Account and set the Intake Client lookup.
        Id clientAccountId = null;
        Boolean shouldQueueClientAccountResolution = false;
        try {
            clientAccountId = resolveClientAccountId(intake);
        } catch (UnbounceIntakeServiceException e) {
            System.debug(LoggingLevel.WARN, 'Skipping client Account creation: ' + e.getMessage());
            shouldQueueClientAccountResolution = true;
        }
        if (clientAccountId != null) {
            intake.litify_pm__Client__c = clientAccountId;
        } else if (String.isNotBlank((String) intake.get('litify_pm__Email__c'))) {
            shouldQueueClientAccountResolution = true;
        }

        String referredByPartyName = config != null ? config.referredByPartyName : null;
        Id referredByPartyId = resolveReferredByPartyId(referredByPartyName);
        if (referredByPartyId != null) {
            intake.Referred_By__c = referredByPartyId;
        }

        // Case Type lookup by the configured payload key.
        String caseTypeFromPayload = getPayloadString(
            mappedPayload,
            new List<String>{ 'caseType', 'casetype', 'case_type' }
        );
        if (String.isNotBlank(caseTypeFromPayload)) {
            applyCaseTypeRouting(intake, caseTypeFromPayload);
            String litifyCaseTypeName = getLitifyCaseTypeName(caseTypeFromPayload);
            Id caseTypeId = resolveCaseTypeId(litifyCaseTypeName);
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
            if (clientAccountId == null && shouldReapplyMappedFields(intake)) {
                update intake;
            }
            if (shouldQueueClientAccountResolution) {
                publishClientAccountRequest(intake.Id);
            }
            return intake;
        } catch (DmlException e) {
            throw new UnbounceIntakeServiceException('Failed to create intake: ' + e.getMessage());
        }
    }

    public static void processClientAccountRequests(List<Unbounce_Client_Account_Request__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        Set<Id> intakeIds = new Set<Id>();
        for (Unbounce_Client_Account_Request__e eventRecord : events) {
            Id intakeId = parseId(eventRecord.Intake_Id__c);
            if (intakeId != null) {
                intakeIds.add(intakeId);
            }
        }
        if (intakeIds.isEmpty()) {
            return;
        }

        Map<Id, litify_pm__Intake__c> intakeById = new Map<Id, litify_pm__Intake__c>([
            SELECT Id,
                   litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__Client__c
            FROM litify_pm__Intake__c
            WHERE Id IN :intakeIds
        ]);

        List<litify_pm__Intake__c> updates = new List<litify_pm__Intake__c>();
        for (Id intakeId : intakeIds) {
            litify_pm__Intake__c intake = intakeById.get(intakeId);
            if (intake == null ||
                intake.litify_pm__Client__c != null ||
                String.isBlank((String) intake.get('litify_pm__Email__c'))) {
                continue;
            }

            try {
                Id clientId = resolveClientAccountId(intake);
                if (clientId != null) {
                    updates.add(new litify_pm__Intake__c(
                        Id = intake.Id,
                        litify_pm__Client__c = clientId
                    ));
                }
            } catch (UnbounceIntakeServiceException e) {
                System.debug(
                    LoggingLevel.WARN,
                    'Deferred client Account creation failed for Intake ' + intake.Id + ': ' + e.getMessage()
                );
            }
        }

        if (!updates.isEmpty()) {
            update updates;
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
            if (Test.isRunningTest() && forcedClientAccountCreateFailureMessage != null) {
                throw new UnbounceIntakeServiceException(forcedClientAccountCreateFailureMessage);
            }
            Schema.DescribeSObjectResult dr = Account.SObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = dr.fields.getMap();
            Map<String, Schema.SObjectField> intakeFieldMap = litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();

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
            if (fieldMap.containsKey('litify_pm__First_Name__c') && String.isNotBlank(firstName)) {
                a.put('litify_pm__First_Name__c', firstName);
            }
            if (fieldMap.containsKey('litify_pm__Last_Name__c') && String.isNotBlank(lastName)) {
                a.put('litify_pm__Last_Name__c', lastName);
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
                String intakeMobile = intakeFieldMap.containsKey('litify_pm__Phone_Mobile__c')
                    ? (String) intake.get('litify_pm__Phone_Mobile__c')
                    : null;
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

    private static Boolean shouldReapplyMappedFields(litify_pm__Intake__c intake) {
        return String.isNotBlank((String) intake.get('litify_pm__First_Name__c')) ||
            String.isNotBlank((String) intake.get('litify_pm__Last_Name__c')) ||
            String.isNotBlank((String) intake.get('litify_pm__Email__c')) ||
            String.isNotBlank((String) intake.get('litify_pm__Phone__c'));
    }

    private static void publishClientAccountRequest(Id intakeId) {
        if (intakeId == null) {
            return;
        }
        try {
            EventBus.publish(new Unbounce_Client_Account_Request__e(
                Intake_Id__c = String.valueOf(intakeId)
            ));
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'Failed to publish deferred client Account creation request for Intake ' + intakeId + ': ' + e.getMessage()
            );
        }
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value.trim();
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

    private static void applyCaseTypeRouting(litify_pm__Intake__c intake, String caseTypeFromPayload) {
        setIntakePicklistIfAllowed(intake, 'Case_Type__c', caseTypeFromPayload);

        if (isMvaCaseType(caseTypeFromPayload)) {
            setIntakePicklistIfAllowed(intake, 'Type__c', 'Personal Injury');
        }
    }

    private static String getLitifyCaseTypeName(String caseTypeFromPayload) {
        return isMvaCaseType(caseTypeFromPayload) ? 'PI - MVA' : caseTypeFromPayload;
    }

    private static Boolean isMvaCaseType(String caseTypeFromPayload) {
        return String.isNotBlank(caseTypeFromPayload) &&
            caseTypeFromPayload.trim().toUpperCase() == 'MVA';
    }

    private static void setIntakePicklistIfAllowed(litify_pm__Intake__c intake, String fieldName, String value) {
        if (String.isBlank(fieldName) || String.isBlank(value)) {
            return;
        }
        try {
            Map<String, Schema.SObjectField> intakeFields = litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();
            if (!intakeFields.containsKey(fieldName)) {
                return;
            }
            Schema.DescribeFieldResult fieldDescribe = intakeFields.get(fieldName).getDescribe();
            if (fieldDescribe.getType() != Schema.DisplayType.Picklist) {
                return;
            }
            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive() && entry.getValue() == value) {
                    intake.put(fieldName, value);
                    return;
                }
            }
        } catch (Exception e) {
            return;
        }
    }

    private static String getPayloadString(Map<String, Object> payload, List<String> keys) {
        String value = getString(payload, keys);
        if (String.isNotBlank(value)) {
            return value;
        }
        if (payload.containsKey('data') && payload.get('data') instanceof Map<String, Object>) {
            return getString((Map<String, Object>) payload.get('data'), keys);
        }
        return null;
    }

    private static String getString(Map<String, Object> data, List<String> keys) {
        for (String key : keys) {
            Object value = data.get(key);
            String normalizedValue = normalizeStringValue(value);
            if (String.isNotBlank(normalizedValue)) {
                return normalizedValue;
            }
        }
        return null;
    }

    private static String normalizeStringValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof List<Object>) {
            for (Object item : (List<Object>) value) {
                String normalizedItem = normalizeStringValue(item);
                if (String.isNotBlank(normalizedItem)) {
                    return normalizedItem;
                }
            }
            return null;
        }

        String normalized = String.valueOf(value);
        return String.isNotBlank(normalized) ? normalized.trim() : null;
    }

    private static void setBooleanFieldIfExists(SObject record, String fieldName, Boolean value) {
        setFieldIfExists(record, fieldName, value);
    }

    private static void setFieldIfExists(SObject record, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName)) {
            return;
        }
        try {
            Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
            if (!fields.containsKey(fieldName)) {
                return;
            }
            record.put(fieldName, value);
        } catch (Exception e) {
            return;
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
