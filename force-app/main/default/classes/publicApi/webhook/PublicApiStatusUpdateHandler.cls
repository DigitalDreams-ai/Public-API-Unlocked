public without sharing class PublicApiStatusUpdateHandler {
    @TestVisible
    static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';

    public static void handleAfterUpdate(List<PublicApi_Submission__c> newRecords, Map<Id, PublicApi_Submission__c> oldMap) {
        if (newRecords == null || newRecords.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> configIds = new Set<Id>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            if (newRecord != null && newRecord.PublicApi_Integration_Config__c != null) {
                configIds.add(newRecord.PublicApi_Integration_Config__c);
            }
        }
        if (configIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(configIds);
        List<PublicApiOutboundTriggerService.ChangeRequest> requests =
            new List<PublicApiOutboundTriggerService.ChangeRequest>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            if (newRecord == null || newRecord.PublicApi_Integration_Config__c == null) {
                continue;
            }

            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            PublicApiConfigService.Config config = configsById.get(newRecord.PublicApi_Integration_Config__c);
            if (oldRecord == null || config == null || !supportsSubmissionTrigger(config)) {
                continue;
            }

            String triggerFieldName = PublicApiOutboundTriggerService.getConfiguredTriggerFieldName(config);
            if (!hasField(newRecord, triggerFieldName) || !didFieldChange(newRecord, oldRecord, triggerFieldName)) {
                continue;
            }

            requests.add(new PublicApiOutboundTriggerService.ChangeRequest(
                newRecord.Id,
                newRecord.PublicApi_Integration_Config__c,
                normalizeValue(oldRecord.get(triggerFieldName)),
                normalizeValue(newRecord.get(triggerFieldName)),
                System.now(),
                UserInfo.getSessionId()
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
        if (config == null) {
            return false;
        }
        return SUBMISSION_OBJECT_API_NAME.equalsIgnoreCase(
            String.isBlank(config.targetObjectApiName) ? SUBMISSION_OBJECT_API_NAME : config.targetObjectApiName
        );
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
