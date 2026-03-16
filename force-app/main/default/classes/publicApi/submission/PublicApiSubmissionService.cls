public without sharing class PublicApiSubmissionService {
    @TestVisible static final Integer RAW_PAYLOAD_MAX_LENGTH = 131072;
    @TestVisible public static final String AUDIT_STATUS_RECEIVED = 'Received';
    @TestVisible public static final String AUDIT_STATUS_SUCCEEDED = 'Succeeded';
    @TestVisible public static final String AUDIT_STATUS_FAILED = 'Failed';
    @TestVisible public static final String RELATED_STATUS_NOT_CONFIGURED = 'NotConfigured';
    @TestVisible public static final String RELATED_STATUS_PENDING_PROCESSING = 'PendingProcessing';
    @TestVisible public static final String RELATED_STATUS_IMMEDIATE_PROCESSED = 'ImmediateProcessed';
    @TestVisible public static final String ERROR_CATEGORY_PAYLOAD = 'PAYLOAD_PARSE_ERROR';
    @TestVisible public static final String ERROR_CATEGORY_CONFIGURATION = 'CONFIGURATION_ERROR';
    @TestVisible public static final String ERROR_CATEGORY_TARGET_DML = 'TARGET_DML_ERROR';
    @TestVisible public static final String ERROR_CATEGORY_UNEXPECTED = 'UNEXPECTED_PROCESSING_ERROR';

    public static SObject createSubmissionFromPublicApi(
        String rawRequestBody,
        String requestContentType,
        PublicApiConfigService.Config config
    ) {
        if (config == null || config.id == null) {
            throw new PublicApiSubmissionServiceException(
                'Public API submission requires a matching active Public API Integration Config record.'
            );
        }

        String targetObjectApiName = String.isBlank(config.targetObjectApiName)
            ? PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
            : config.targetObjectApiName.trim();
        String rawPayload = truncate(
            rawRequestBody,
            RAW_PAYLOAD_MAX_LENGTH
        );
        String effectiveConfigJson = buildEffectiveConfigJson(config, targetObjectApiName);

        PublicApi_Submission__c auditRecord = buildAuditRecord(
            config,
            targetObjectApiName,
            rawPayload,
            requestContentType,
            effectiveConfigJson
        );

        try {
            insert auditRecord;
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            if (!globalDescribe.containsKey(targetObjectApiName)) {
                throw new PublicApiSubmissionServiceException('Submission object not found: ' + targetObjectApiName);
            }

            PublicApiPayloadParser.parsePayload(rawPayload, requestContentType);
            validateSubmissionProcessingConfiguration(
                config.inboundPayloadConfiguration,
                config.relatedRecordConfiguration,
                targetObjectApiName
            );
            publishSubmissionRequest(auditRecord.Id);
            return auditRecord;
        } catch (PublicApiSubmissionServiceException e) {
            String errorCategory = e.getMessage() != null &&
                (e.getMessage().startsWith('Invalid JSON:') || e.getMessage().startsWith('Invalid form-encoded payload'))
                ? ERROR_CATEGORY_PAYLOAD
                : ERROR_CATEGORY_CONFIGURATION;
            markAuditFailure(auditRecord.Id, errorCategory, e.getMessage());
            throw e;
        } catch (DmlException e) {
            markAuditFailure(auditRecord.Id, ERROR_CATEGORY_TARGET_DML, e.getMessage());
            throw new PublicApiSubmissionServiceException('Failed to create submission audit record: ' + e.getMessage());
        } catch (Exception e) {
            markAuditFailure(auditRecord.Id, ERROR_CATEGORY_UNEXPECTED, e.getMessage());
            throw e;
        }
    }

    @TestVisible
    static PublicApi_Submission__c buildAuditRecord(
        PublicApiConfigService.Config config,
        String targetObjectApiName,
        String rawPayload,
        String requestContentType,
        String effectiveConfigJson
    ) {
        return new PublicApi_Submission__c(
            PublicApi_Integration_Config__c = config.id,
            Created_By_PublicApi_API__c = true,
            Received_At__c = System.now(),
            Raw_Payload__c = rawPayload,
            Request_Content_Type__c = truncate(requestContentType, 255),
            Target_Object_API_Name__c = targetObjectApiName,
            Processing_Status__c = AUDIT_STATUS_RECEIVED,
            Related_Record_Status__c = String.isBlank(config.relatedRecordConfiguration)
                ? RELATED_STATUS_NOT_CONFIGURED
                : RELATED_STATUS_PENDING_PROCESSING,
            Effective_Config_JSON__c = effectiveConfigJson
        );
    }

    @TestVisible
    public static void applySuccessAuditState(
        PublicApi_Submission__c auditRecord,
        String targetObjectApiName,
        Id targetRecordId,
        String relatedRecordConfiguration
    ) {
        if (auditRecord == null) {
            return;
        }

        auditRecord.Target_Object_API_Name__c = targetObjectApiName;
        auditRecord.Target_Record_Id__c = targetRecordId == null ? null : String.valueOf(targetRecordId);
        auditRecord.Processing_Status__c = AUDIT_STATUS_SUCCEEDED;
        auditRecord.Processing_Error_Category__c = null;
        auditRecord.Processing_Error_Message__c = null;
        if (!String.isBlank(relatedRecordConfiguration)) {
            auditRecord.Related_Record_Status__c = RELATED_STATUS_IMMEDIATE_PROCESSED;
        } else {
            auditRecord.Related_Record_Status__c = RELATED_STATUS_NOT_CONFIGURED;
        }
    }

    @TestVisible
    static void publishSubmissionRequest(Id auditRecordId) {
        if (auditRecordId == null) {
            return;
        }
        PublicApiSubmissionRequestEventService.publishRequest(auditRecordId);
    }

    @TestVisible
    static void markAuditFailure(Id auditRecordId, String errorCategory, String errorMessage) {
        if (auditRecordId == null) {
            return;
        }

        update new PublicApi_Submission__c(
            Id = auditRecordId,
            Processing_Status__c = AUDIT_STATUS_FAILED,
            Processing_Error_Category__c = errorCategory,
            Processing_Error_Message__c = errorMessage
        );
    }

    @TestVisible
    static String buildEffectiveConfigJson(
        PublicApiConfigService.Config config,
        String targetObjectApiName
    ) {
        Map<String, Object> snapshot = new Map<String, Object>{
            'configId' => config == null ? null : String.valueOf(config.id),
            'targetObjectApiName' => targetObjectApiName,
            'targetRecordTypeDeveloperName' => config == null ? null : config.targetRecordTypeDeveloperName,
            'syncInboundAndOutbound' => config == null ? null : config.syncInboundAndOutbound,
            'inboundPayloadConfiguration' => config == null ? null : config.inboundPayloadConfiguration,
            'outboundPayloadConfiguration' => config == null ? null : config.outboundPayloadConfiguration,
            'relatedRecordConfiguration' => config == null ? null : config.relatedRecordConfiguration,
            'outboundTriggerEnabled' => config == null ? null : config.outboundTriggerEnabled,
            'outboundTriggerFieldName' => config == null ? null : config.outboundTriggerFieldName,
            'outboundTriggerFieldValues' => config == null ? null : config.outboundTriggerFieldValues,
            'outboundWebhookUrl' => config == null ? null : config.statusUpdateWebhookUrl,
            'processingMode' => 'SubmissionOnlyAsync'
        };
        return truncate(JSON.serialize(snapshot), RAW_PAYLOAD_MAX_LENGTH);
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
    static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0 || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    @TestVisible
    public static void validateSubmissionProcessingConfiguration(
        String inboundConfigurationJson,
        String relatedRecordConfigurationJson,
        String targetObjectApiName
    ) {
        if (String.isBlank(inboundConfigurationJson)) {
            throw new PublicApiSubmissionServiceException(
                'Inbound mapping configuration is required on Public API Integration Config.'
            );
        }

        List<PublicApiRequestMappingService.MappingConfig> parsedMappings;
        try {
            parsedMappings = PublicApiRequestMappingService.parseMappings(inboundConfigurationJson);
        } catch (Exception e) {
            throw new PublicApiSubmissionServiceException('Inbound mapping configuration is invalid: ' + e.getMessage());
        }
        if (parsedMappings == null || parsedMappings.isEmpty()) {
            throw new PublicApiSubmissionServiceException(
                'Inbound mapping configuration is invalid: At least one inbound mapping row is required.'
            );
        }

        try {
            PublicApiRequestMappingService.validateInboundMappings(inboundConfigurationJson, targetObjectApiName);
        } catch (PublicApiSubmissionServiceException e) {
            throw new PublicApiSubmissionServiceException('Inbound mapping configuration is invalid: ' + e.getMessage());
        }

        try {
            PublicApiRelatedRecordService.validateRules(relatedRecordConfigurationJson, targetObjectApiName);
        } catch (PublicApiSubmissionServiceException e) {
            throw new PublicApiSubmissionServiceException('Related record configuration is invalid: ' + e.getMessage());
        }
    }
}

