public without sharing class PublicApiRelatedRecordEventService {
    @TestVisible static final Integer EVENT_PAYLOAD_MAX_LENGTH = 131072;
    @TestVisible static final String DEFERRED_RELATED_STATUS_COMPLETED = 'DeferredCompleted';
    @TestVisible static final String DEFERRED_RELATED_STATUS_FAILED = 'DeferredFailed';
    @TestVisible static final String AUDIT_STATUS_FAILED = 'Failed';

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

        List<PublicApiRelatedRecordQueueable.RequestItem> requests =
            new List<PublicApiRelatedRecordQueueable.RequestItem>{
                new PublicApiRelatedRecordQueueable.RequestItem(
                    configId,
                    auditRecordId,
                    targetRecordId,
                    targetObjectApiName,
                    truncate(JSON.serialize(payload), EVENT_PAYLOAD_MAX_LENGTH),
                    truncate(relatedRecordConfigurationJson, EVENT_PAYLOAD_MAX_LENGTH)
                )
            };
        if (Test.isRunningTest()) {
            processRequests(requests);
            return;
        }
        PublicApiRelatedRecordQueueable.enqueue(requests);
    }

    public static void handleEvents(List<PublicApi_Related_Record_Request__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        processRequests(toRequestItems(events));
    }

    public static void processRequests(List<PublicApiRelatedRecordQueueable.RequestItem> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<SObject> recordsToUpdate = new List<SObject>();
        List<PublicApi_Submission__c> auditUpdates = new List<PublicApi_Submission__c>();
        for (PublicApiRelatedRecordQueueable.RequestItem requestItem : requests) {
            try {
                SObject targetRecord = getTargetRecord(
                    requestItem.targetObjectApiName,
                    requestItem.targetRecordId == null ? null : String.valueOf(requestItem.targetRecordId),
                    requestItem.relatedRecordConfigurationJson
                );
                if (targetRecord == null) {
                    continue;
                }

                Map<String, Object> payload = parsePayload(requestItem.payloadJson);
                PublicApiRelatedRecordService.applyRelatedRecordRules(
                    targetRecord,
                    payload,
                    requestItem.relatedRecordConfigurationJson
                );
                recordsToUpdate.add(targetRecord);
                auditUpdates.add(
                    buildAuditUpdate(
                        requestItem.auditRecordId == null ? null : String.valueOf(requestItem.auditRecordId),
                        DEFERRED_RELATED_STATUS_COMPLETED,
                        null,
                        null
                    )
                );
            } catch (Exception e) {
                auditUpdates.add(
                    buildAuditUpdate(
                        requestItem.auditRecordId == null ? null : String.valueOf(requestItem.auditRecordId),
                        DEFERRED_RELATED_STATUS_FAILED,
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

        PublicApi_Submission__c auditUpdate = new PublicApi_Submission__c(
            Id = (Id) auditRecordId,
            Related_Record_Status__c = relatedRecordStatus,
            Processing_Error_Category__c = errorCategory,
            Processing_Error_Message__c = errorMessage
        );
        if (relatedRecordStatus == DEFERRED_RELATED_STATUS_FAILED || !String.isBlank(errorCategory)) {
            auditUpdate.Processing_Status__c = AUDIT_STATUS_FAILED;
        }
        return auditUpdate;
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

    @TestVisible
    static List<PublicApiRelatedRecordQueueable.RequestItem> toRequestItems(
        List<PublicApi_Related_Record_Request__e> events
    ) {
        List<PublicApiRelatedRecordQueueable.RequestItem> items =
            new List<PublicApiRelatedRecordQueueable.RequestItem>();
        if (events == null) {
            return items;
        }

        for (PublicApi_Related_Record_Request__e requestEvent : events) {
            items.add(new PublicApiRelatedRecordQueueable.RequestItem(
                parseId(requestEvent == null ? null : requestEvent.Config_Id__c),
                parseId(requestEvent == null ? null : requestEvent.Audit_Record_Id__c),
                parseId(requestEvent == null ? null : requestEvent.Target_Record_Id__c),
                requestEvent == null ? null : requestEvent.Target_Object_API_Name__c,
                requestEvent == null ? null : requestEvent.Payload_JSON__c,
                requestEvent == null ? null : requestEvent.Related_Record_Configuration_JSON__c
            ));
        }
        return items;
    }

    private static Id parseId(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        try {
            return (Id) rawValue.trim();
        } catch (Exception e) {
            return null;
        }
    }
}
