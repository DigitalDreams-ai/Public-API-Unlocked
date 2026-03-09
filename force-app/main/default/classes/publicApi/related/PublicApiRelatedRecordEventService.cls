public without sharing class PublicApiRelatedRecordEventService {
    @TestVisible static final Integer EVENT_PAYLOAD_MAX_LENGTH = 131072;

    public static void publishRequest(
        Id configId,
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
        for (PublicApi_Related_Record_Request__e requestEvent : events) {
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
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
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
        for (PublicApiRelatedRecordConfig.Rule rule :
            PublicApiRelatedRecordConfig.parseRules(relatedRecordConfigurationJson)) {
            if (rule != null && String.isNotBlank(rule.targetLookupField)) {
                fieldNames.add(rule.targetLookupField.trim());
            }
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
}
