public without sharing class PublicApiIntakeService {
    @TestVisible static final Integer RAW_PAYLOAD_MAX_LENGTH = 131072;
    @TestVisible static final String AUDIT_STATUS_RECEIVED = 'Received';
    @TestVisible static final String AUDIT_STATUS_SUCCEEDED = 'Succeeded';
    @TestVisible static final String AUDIT_STATUS_FAILED = 'Failed';
    @TestVisible static final String RELATED_STATUS_NOT_CONFIGURED = 'NotConfigured';
    @TestVisible static final String RELATED_STATUS_IMMEDIATE_PROCESSED = 'ImmediateProcessed';
    @TestVisible static final String RELATED_STATUS_DEFERRED_PENDING = 'DeferredPending';
    @TestVisible static final String ERROR_CATEGORY_CONFIGURATION = 'CONFIGURATION_ERROR';
    @TestVisible static final String ERROR_CATEGORY_TARGET_DML = 'TARGET_DML_ERROR';
    @TestVisible static final String ERROR_CATEGORY_UNEXPECTED = 'UNEXPECTED_PROCESSING_ERROR';

    public static SObject createIntakeFromPublicApi(
        Map<String, Object> payload,
        PublicApiConfigService.Config config
    ) {
        return createIntakeFromPublicApi(
            payload,
            payload == null ? null : JSON.serialize(payload),
            null,
            config
        );
    }

    public static SObject createIntakeFromPublicApi(
        Map<String, Object> payload,
        String rawRequestBody,
        String requestContentType,
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

        String immediateRelatedRecordConfiguration =
            PublicApiRelatedRecordService.getImmediateRuleJson(config.relatedRecordConfiguration);
        String deferredRelatedRecordConfiguration =
            PublicApiRelatedRecordService.getDeferredRuleJson(config.relatedRecordConfiguration);
        String rawPayload = truncate(
            String.isBlank(rawRequestBody) ? JSON.serialize(payload) : rawRequestBody,
            RAW_PAYLOAD_MAX_LENGTH
        );
        String effectiveConfigJson = buildEffectiveConfigJson(
            config,
            targetObjectApiName,
            immediateRelatedRecordConfiguration,
            deferredRelatedRecordConfiguration
        );

        PublicApi_Submission__c auditRecord = buildAuditRecord(
            config,
            targetObjectApiName,
            rawPayload,
            requestContentType,
            effectiveConfigJson
        );
        Boolean auditIsTargetRecord =
            targetObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME;
        SObject targetRecord = auditIsTargetRecord
            ? (SObject) auditRecord
            : globalDescribe.get(targetObjectApiName).newSObject();

        if (auditIsTargetRecord) {
            PublicApiRecordTypeService.applyTargetRecordType(targetRecord, config.targetRecordTypeDeveloperName);
        }

        insert auditRecord;
        if (auditIsTargetRecord) {
            auditRecord.Target_Record_Id__c = String.valueOf(auditRecord.Id);
        }

        try {
            validateInboundConfiguration(
                config.inboundPayloadConfiguration,
                config.relatedRecordConfiguration,
                targetObjectApiName
            );

            if (!auditIsTargetRecord) {
                PublicApiRecordTypeService.applyTargetRecordType(targetRecord, config.targetRecordTypeDeveloperName);
            }

            PublicApiRequestMappingService.applyInboundMappings(
                targetRecord,
                payload,
                config.inboundPayloadConfiguration,
                targetObjectApiName
            );
            PublicApiRelatedRecordService.applyRelatedRecordRules(
                targetRecord,
                payload,
                immediateRelatedRecordConfiguration
            );

            if (auditIsTargetRecord) {
                applySuccessAuditState(
                    auditRecord,
                    targetObjectApiName,
                    auditRecord.Id,
                    immediateRelatedRecordConfiguration,
                    deferredRelatedRecordConfiguration
                );
                update auditRecord;
                publishDeferredRequestIfNeeded(
                    config,
                    auditRecord.Id,
                    auditRecord.Id,
                    targetObjectApiName,
                    payload,
                    deferredRelatedRecordConfiguration
                );
                return auditRecord;
            }

            insert targetRecord;
            applySuccessAuditState(
                auditRecord,
                targetObjectApiName,
                targetRecord.Id,
                immediateRelatedRecordConfiguration,
                deferredRelatedRecordConfiguration
            );
            update auditRecord;
            publishDeferredRequestIfNeeded(
                config,
                auditRecord.Id,
                targetRecord.Id,
                targetObjectApiName,
                payload,
                deferredRelatedRecordConfiguration
            );
            return targetRecord;
        } catch (PublicApiIntakeServiceException e) {
            markAuditFailure(auditRecord.Id, ERROR_CATEGORY_CONFIGURATION, e.getMessage());
            throw e;
        } catch (DmlException e) {
            markAuditFailure(auditRecord.Id, ERROR_CATEGORY_TARGET_DML, e.getMessage());
            throw new PublicApiIntakeServiceException('Failed to create submission: ' + e.getMessage());
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
                : RELATED_STATUS_IMMEDIATE_PROCESSED,
            Effective_Config_JSON__c = effectiveConfigJson
        );
    }

    @TestVisible
    static void applySuccessAuditState(
        PublicApi_Submission__c auditRecord,
        String targetObjectApiName,
        Id targetRecordId,
        String immediateRelatedRecordConfiguration,
        String deferredRelatedRecordConfiguration
    ) {
        if (auditRecord == null) {
            return;
        }

        auditRecord.Target_Object_API_Name__c = targetObjectApiName;
        auditRecord.Target_Record_Id__c = targetRecordId == null ? null : String.valueOf(targetRecordId);
        auditRecord.Processing_Status__c = AUDIT_STATUS_SUCCEEDED;
        auditRecord.Processing_Error_Category__c = null;
        auditRecord.Processing_Error_Message__c = null;
        if (!String.isBlank(deferredRelatedRecordConfiguration)) {
            auditRecord.Related_Record_Status__c = RELATED_STATUS_DEFERRED_PENDING;
        } else if (!String.isBlank(immediateRelatedRecordConfiguration)) {
            auditRecord.Related_Record_Status__c = RELATED_STATUS_IMMEDIATE_PROCESSED;
        } else {
            auditRecord.Related_Record_Status__c = RELATED_STATUS_NOT_CONFIGURED;
        }
    }

    @TestVisible
    static void publishDeferredRequestIfNeeded(
        PublicApiConfigService.Config config,
        Id auditRecordId,
        Id targetRecordId,
        String targetObjectApiName,
        Map<String, Object> payload,
        String deferredRelatedRecordConfiguration
    ) {
        if (String.isBlank(deferredRelatedRecordConfiguration)) {
            return;
        }

        PublicApiRelatedRecordEventService.publishRequest(
            config.id,
            auditRecordId,
            targetRecordId,
            targetObjectApiName,
            payload,
            deferredRelatedRecordConfiguration
        );
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
        String targetObjectApiName,
        String immediateRelatedRecordConfiguration,
        String deferredRelatedRecordConfiguration
    ) {
        Map<String, Object> snapshot = new Map<String, Object>{
            'configId' => config == null ? null : String.valueOf(config.id),
            'targetObjectApiName' => targetObjectApiName,
            'targetRecordTypeDeveloperName' => config == null ? null : config.targetRecordTypeDeveloperName,
            'syncInboundAndOutbound' => config == null ? null : config.syncInboundAndOutbound,
            'inboundPayloadConfiguration' => config == null ? null : config.inboundPayloadConfiguration,
            'outboundPayloadConfiguration' => config == null ? null : config.outboundPayloadConfiguration,
            'relatedRecordConfiguration' => String.isBlank(deferredRelatedRecordConfiguration)
                ? immediateRelatedRecordConfiguration
                : deferredRelatedRecordConfiguration,
            'outboundTriggerEnabled' => config == null ? null : config.outboundTriggerEnabled,
            'outboundTriggerFieldName' => config == null ? null : config.outboundTriggerFieldName,
            'outboundTriggerFieldValues' => config == null ? null : config.outboundTriggerFieldValues,
            'outboundWebhookUrl' => config == null ? null : config.statusUpdateWebhookUrl
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
