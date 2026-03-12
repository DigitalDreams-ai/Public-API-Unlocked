public without sharing class PublicApiIntakeService {
    @TestVisible
    static final Integer RAW_PAYLOAD_MAX_LENGTH = 131072;

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
        String targetObjectApiName = String.isBlank(config.targetObjectApiName)
            ? PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
            : config.targetObjectApiName.trim();
        if (!globalDescribe.containsKey(targetObjectApiName)) {
            throw new PublicApiIntakeServiceException('Submission object not found: ' + targetObjectApiName);
        }
        validateInboundConfiguration(
            config.inboundPayloadConfiguration,
            config.relatedRecordConfiguration,
            targetObjectApiName
        );
        String immediateRelatedRecordConfiguration =
            PublicApiRelatedRecordService.getImmediateRulesJson(config.relatedRecordConfiguration);
        String deferredRelatedRecordConfiguration =
            PublicApiRelatedRecordService.getDeferredRulesJson(config.relatedRecordConfiguration);
        SObject submission = globalDescribe.get(targetObjectApiName).newSObject();
        PublicApiRecordTypeService.applyTargetRecordType(submission, config.targetRecordTypeDeveloperName);
        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            config.inboundPayloadConfiguration,
            targetObjectApiName
        );
        PublicApiRelatedRecordService.applyRelatedRecordRules(
            submission,
            payload,
            immediateRelatedRecordConfiguration
        );

        putIfFieldExists(submission, 'PublicApi_Integration_Config__c', config.id);
        putIfFieldExists(submission, 'Created_By_PublicApi_API__c', true);
        putIfFieldExists(submission, 'Received_At__c', System.now());
        putIfFieldExists(submission, 'Status__c', defaultStatus(submission));
        putIfFieldExists(submission, 'Raw_Payload__c', truncate(JSON.serialize(payload), RAW_PAYLOAD_MAX_LENGTH));

        try {
            insert submission;
            PublicApiRelatedRecordEventService.publishRequest(
                config.id,
                submission.Id,
                targetObjectApiName,
                payload,
                deferredRelatedRecordConfiguration
            );
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
        Map<String, Schema.SObjectField> fieldMap = submission.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey('Status__c')) {
            return null;
        }
        Object existing = submission.get('Status__c');
        if (existing != null && String.isNotBlank(String.valueOf(existing))) {
            return String.valueOf(existing);
        }

        Schema.DescribeFieldResult describe = fieldMap.get('Status__c').getDescribe();
        Object defaultValue = describe == null ? null : describe.getDefaultValue();
        if (defaultValue != null && String.isNotBlank(String.valueOf(defaultValue))) {
            return String.valueOf(defaultValue);
        }

        if (describe != null && describe.getType() == Schema.DisplayType.Picklist) {
            for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                if (entry != null && entry.isDefaultValue()) {
                    return entry.getValue();
                }
            }
        }
        return null;
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
    private static void validateInboundConfiguration(
        String inboundConfigurationJson,
        String relatedRecordConfigurationJson,
        String targetObjectApiName
    ) {
        if (String.isBlank(inboundConfigurationJson)) {
            throw new PublicApiIntakeServiceException(
                'Inbound mapping configuration is required on Public API Integration Config.'
            );
        }

        List<PublicApiRequestMappingService.MappingConfig> parsedMappings;
        try {
            parsedMappings = PublicApiRequestMappingService.parseMappings(inboundConfigurationJson);
        } catch (Exception e) {
            throw new PublicApiIntakeServiceException('Inbound mapping configuration is invalid: ' + e.getMessage());
        }
        if (parsedMappings == null || parsedMappings.isEmpty()) {
            throw new PublicApiIntakeServiceException(
                'Inbound mapping configuration is invalid: At least one inbound mapping row is required.'
            );
        }

        try {
            PublicApiRequestMappingService.validateInboundMappings(inboundConfigurationJson, targetObjectApiName);
        } catch (PublicApiIntakeServiceException e) {
            throw new PublicApiIntakeServiceException('Inbound mapping configuration is invalid: ' + e.getMessage());
        }

        try {
            PublicApiRelatedRecordService.validateRules(relatedRecordConfigurationJson, targetObjectApiName);
        } catch (PublicApiIntakeServiceException e) {
            throw new PublicApiIntakeServiceException('Related record configuration is invalid: ' + e.getMessage());
        }
    }
}
