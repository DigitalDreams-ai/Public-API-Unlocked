public without sharing class PublicApiRelatedRecordEventService {
    @TestVisible static final Integer EVENT_PAYLOAD_MAX_LENGTH = 131072;

    public static void publishRequest(
        Id configId,
        Id auditRecordId,
        Id targetRecordId,
        String targetObjectApiName,
        Map<String, Object> payload,
        String relatedRecordConfigurationJson
    ) {
        if (configId == null ||
            targetRecordId == null ||
            String.isBlank(targetObjectApiName) ||
            String.isBlank(relatedRecordConfigurationJson)) {
            return;
        }

        PublicApi_Related_Record_Request__e requestEvent = new PublicApi_Related_Record_Request__e(
            Config_Id__c = String.valueOf(configId),
            Audit_Record_Id__c = auditRecordId == null ? null : String.valueOf(auditRecordId),
            Target_Record_Id__c = String.valueOf(targetRecordId),
            Target_Object_API_Name__c = targetObjectApiName,
            Payload_JSON__c = truncate(JSON.serialize(payload), EVENT_PAYLOAD_MAX_LENGTH),
            Related_Record_Configuration_JSON__c =
                truncate(relatedRecordConfigurationJson, EVENT_PAYLOAD_MAX_LENGTH)
        );
        EventBus.publish(new List<PublicApi_Related_Record_Request__e>{ requestEvent });
    }

    public static void handleEvents(List<PublicApi_Related_Record_Request__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<SObject> recordsToUpdate = new List<SObject>();
        List<PublicApi_Submission__c> auditUpdates = new List<PublicApi_Submission__c>();
        for (PublicApi_Related_Record_Request__e requestEvent : events) {
            try {
                SObject targetRecord = getTargetRecord(
                    requestEvent.Target_Object_API_Name__c,
                    requestEvent.Target_Record_Id__c,
                    requestEvent.Related_Record_Configuration_JSON__c
                );
                if (targetRecord == null) {
                    continue;
                }

                Map<String, Object> payload = parsePayload(requestEvent.Payload_JSON__c);
                PublicApiRelatedRecordService.applyRelatedRecordRules(
                    targetRecord,
                    payload,
                    requestEvent.Related_Record_Configuration_JSON__c
                );
                recordsToUpdate.add(targetRecord);
                auditUpdates.add(buildAuditUpdate(requestEvent.Audit_Record_Id__c, 'DeferredCompleted', null, null));
            } catch (Exception e) {
                auditUpdates.add(
                    buildAuditUpdate(
                        requestEvent.Audit_Record_Id__c,
                        'DeferredFailed',
                        'RELATED_RECORD_DEFERRED_ERROR',
                        e.getMessage()
                    )
                );
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
        persistAuditUpdates(auditUpdates);
    }

    @TestVisible
    static SObject getTargetRecord(
        String targetObjectApiName,
        String targetRecordId,
        String relatedRecordConfigurationJson
    ) {
        if (String.isBlank(targetObjectApiName) ||
            String.isBlank(targetRecordId) ||
            String.isBlank(relatedRecordConfigurationJson)) {
            return null;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(targetObjectApiName)) {
            return null;
        }

        Set<String> fieldNames = new Set<String>{ 'Id' };
        PublicApiRelatedRecordConfig.Rule rule =
            PublicApiRelatedRecordConfig.parseRule(relatedRecordConfigurationJson);
        if (rule != null && String.isNotBlank(rule.targetLookupField)) {
            fieldNames.add(rule.targetLookupField.trim());
        }

        return Database.query(
            'SELECT ' + String.join(new List<String>(fieldNames), ', ') +
            ' FROM ' + targetObjectApiName +
            ' WHERE Id = :targetRecordId LIMIT 1'
        );
    }

    @TestVisible
    static Map<String, Object> parsePayload(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return new Map<String, Object>();
        }

        Object parsed = JSON.deserializeUntyped(payloadJson);
        return parsed instanceof Map<String, Object>
            ? (Map<String, Object>) parsed
            : new Map<String, Object>();
    }

    @TestVisible
    static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0 || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    @TestVisible
    static PublicApi_Submission__c buildAuditUpdate(
        String auditRecordId,
        String relatedRecordStatus,
        String errorCategory,
        String errorMessage
    ) {
        if (String.isBlank(auditRecordId)) {
            return null;
        }

        return new PublicApi_Submission__c(
            Id = (Id) auditRecordId,
            Related_Record_Status__c = relatedRecordStatus,
            Processing_Error_Category__c = errorCategory,
            Processing_Error_Message__c = errorMessage
        );
    }

    private static void persistAuditUpdates(List<PublicApi_Submission__c> auditUpdates) {
        List<PublicApi_Submission__c> filteredUpdates = new List<PublicApi_Submission__c>();
        for (PublicApi_Submission__c auditUpdate : auditUpdates) {
            if (auditUpdate != null && auditUpdate.Id != null) {
                filteredUpdates.add(auditUpdate);
            }
        }
        if (!filteredUpdates.isEmpty()) {
            update filteredUpdates;
        }
    }
}
