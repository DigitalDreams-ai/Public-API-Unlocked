public without sharing class PublicApiIntakeService {
    @TestVisible
    static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';
    @TestVisible
    static final Integer RAW_PAYLOAD_MAX_LENGTH = 131072;
    @TestVisible
    static final String DIRECTION_INBOUND = 'Inbound';

    public static SObject createIntakeFromPublicApi(
        Map<String, Object> payload,
        PublicApiConfigService.Config config
    ) {
        if (payload == null) {
            throw new PublicApiIntakeServiceException('Payload cannot be null.');
        }
        if (config == null || config.id == null) {
            throw new PublicApiIntakeServiceException(
                'Public API submission requires a matching active Public API Integration Config record.'
            );
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(SUBMISSION_OBJECT_API_NAME)) {
            throw new PublicApiIntakeServiceException('Submission object not found: ' + SUBMISSION_OBJECT_API_NAME);
        }
        validateInboundMappings(config.requestFieldMappingsConfiguration);

        SObject submission = globalDescribe.get(SUBMISSION_OBJECT_API_NAME).newSObject();
        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            config.requestFieldMappingsConfiguration,
            PublicApiRequestMappingService.getDefaultDirection()
        );

        putIfFieldExists(submission, 'PublicApi_Integration_Config__c', config.id);
        putIfFieldExists(submission, 'Created_By_PublicApi_API__c', true);
        putIfFieldExists(submission, 'Status__c', defaultStatus(submission));
        putIfFieldExists(submission, 'Raw_Payload__c', truncate(JSON.serialize(payload), RAW_PAYLOAD_MAX_LENGTH));

        try {
            insert submission;
            PublicApiIntakeTrackingService.trackIntake(submission.Id, config.id);
            return submission;
        } catch (DmlException e) {
            throw new PublicApiIntakeServiceException('Failed to create submission: ' + e.getMessage());
        }
    }

    @TestVisible
    private static String defaultStatus(SObject submission) {
        if (submission == null) {
            return null;
        }
        Object existing = submission.get('Status__c');
        if (existing != null && String.isNotBlank(String.valueOf(existing))) {
            return String.valueOf(existing);
        }
        return 'New';
    }

    @TestVisible
    private static void putIfFieldExists(SObject record, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName)) {
            return;
        }
        Map<String, Schema.SObjectField> fieldMap = record.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldName)) {
            return;
        }
        record.put(fieldName, value);
    }

    @TestVisible
    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0 || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    @TestVisible
    private static void validateInboundMappings(String mappingConfigurationJson) {
        if (String.isBlank(mappingConfigurationJson)) {
            throw new PublicApiIntakeServiceException(
                'Inbound mapping configuration is required on Public API Integration Config.'
            );
        }
        try {
            PublicApiRequestMappingService.validateMappings(mappingConfigurationJson, DIRECTION_INBOUND);
        } catch (PublicApiIntakeServiceException e) {
            throw new PublicApiIntakeServiceException('Inbound mapping configuration is invalid: ' + e.getMessage());
        }
    }
}
