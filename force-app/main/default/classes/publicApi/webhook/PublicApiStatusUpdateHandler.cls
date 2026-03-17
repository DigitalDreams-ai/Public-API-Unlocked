public without sharing class PublicApiStatusUpdateHandler {
    @TestVisible
    static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';
    @TestVisible
    static final String CONFIG_LOOKUP_FIELD_API_NAME = 'PublicApi_Integration_Config__c';

    public static void handleAfterUpdate(List<PublicApi_Submission__c> newRecords, Map<Id, PublicApi_Submission__c> oldMap) {
        if (newRecords == null || newRecords.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> linkedConfigIds = new Set<Id>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            Id configId = getLinkedConfigId(newRecord);
            if (configId != null) {
                linkedConfigIds.add(configId);
            }
        }

        Map<Id, PublicApiConfigService.Config> linkedConfigsById = linkedConfigIds.isEmpty()
            ? new Map<Id, PublicApiConfigService.Config>()
            : PublicApiConfigService.getConfigsById(linkedConfigIds);
        List<PublicApiOutboundTriggerService.ChangeRequest> requests =
            new List<PublicApiOutboundTriggerService.ChangeRequest>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            if (newRecord == null) {
                continue;
            }

            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord == null) {
                continue;
            }

            PublicApiConfigService.Config config = linkedConfigsById.get(newRecord.PublicApi_Integration_Config__c);
            if (config == null) {
                continue;
            }

            String triggerFieldName = PublicApiOutboundTriggerService.getConfiguredTriggerFieldName(config);
            if (!hasField(newRecord, triggerFieldName) || !didFieldChange(newRecord, oldRecord, triggerFieldName)) {
                continue;
            }

            requests.add(new PublicApiOutboundTriggerService.ChangeRequest(
                newRecord.Id,
                config.id,
                normalizeValue(oldRecord.get(triggerFieldName)),
                normalizeValue(newRecord.get(triggerFieldName)),
                System.now()
            ));
        }
        PublicApiOutboundTriggerService.enqueueFieldChanges(requests);
    }

    @TestVisible
    static Boolean didStatusChange(PublicApi_Submission__c newRecord, PublicApi_Submission__c oldRecord) {
        return didFieldChange(newRecord, oldRecord, 'Status__c');
    }

    @TestVisible
    static Boolean didFieldChange(SObject newRecord, SObject oldRecord, String fieldApiName) {
        if (newRecord == null || oldRecord == null || String.isBlank(fieldApiName)) {
            return false;
        }
        return normalizeValue(newRecord.get(fieldApiName)) != normalizeValue(oldRecord.get(fieldApiName));
    }

    @TestVisible
    static Boolean supportsSubmissionTrigger(PublicApiConfigService.Config config) {
        return config != null;
    }

    @TestVisible
    static List<PublicApiConfigService.Config> getApplicableConfigs(
        SObject record,
        Map<Id, PublicApiConfigService.Config> linkedConfigsById,
        List<PublicApiConfigService.Config> objectConfigs
    ) {
        List<PublicApiConfigService.Config> configs = new List<PublicApiConfigService.Config>();
        Id linkedConfigId = getLinkedConfigId(record);
        if (linkedConfigId != null) {
            PublicApiConfigService.Config linkedConfig =
                linkedConfigsById == null ? null : linkedConfigsById.get(linkedConfigId);
            if (linkedConfig != null) {
                configs.add(linkedConfig);
            }
            return configs;
        }

        return configs;
    }

    @TestVisible
    static Id getLinkedConfigId(SObject record) {
        if (!hasField(record, CONFIG_LOOKUP_FIELD_API_NAME)) {
            return null;
        }

        Object rawValue = record.get(CONFIG_LOOKUP_FIELD_API_NAME);
        if (rawValue == null) {
            return null;
        }
        return (Id) rawValue;
    }

    @TestVisible
    static Boolean hasField(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) {
            return false;
        }
        return record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName);
    }

    @TestVisible
    static Boolean shouldSendStatusUpdate(PublicApiConfigService.Config config, String status) {
        return PublicApiOutboundTriggerService.shouldSendOutboundTrigger(config, status);
    }

    @TestVisible
    static Boolean isOutboundTriggerEnabled(PublicApiConfigService.Config config) {
        return PublicApiOutboundTriggerService.isOutboundTriggerEnabled(config);
    }

    @TestVisible
    static Set<String> getConfiguredTriggerStatuses(PublicApiConfigService.Config config) {
        return PublicApiOutboundTriggerService.getConfiguredTriggerFieldValues(config);
    }

    @TestVisible
    static Set<String> parseTriggerStatuses(String rawValues) {
        return PublicApiOutboundTriggerService.parseTriggerFieldValues(rawValues);
    }

    private static String normalizeValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }
}
