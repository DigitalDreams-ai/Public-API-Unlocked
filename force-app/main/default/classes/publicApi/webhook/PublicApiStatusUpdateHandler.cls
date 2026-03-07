public without sharing class PublicApiStatusUpdateHandler {
    public static void handleAfterUpdate(List<PublicApi_Submission__c> newRecords, Map<Id, PublicApi_Submission__c> oldMap) {
        if (newRecords == null || newRecords.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        List<PublicApiOutboundTriggerService.StatusChangeRequest> requests =
            new List<PublicApiOutboundTriggerService.StatusChangeRequest>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord == null || !didStatusChange(newRecord, oldRecord)) {
                continue;
            }
            if (newRecord.PublicApi_Integration_Config__c == null) {
                continue;
            }
            requests.add(new PublicApiOutboundTriggerService.StatusChangeRequest(
                newRecord.Id,
                newRecord.PublicApi_Integration_Config__c,
                normalizeStatus(oldRecord.Status__c),
                normalizeStatus(newRecord.Status__c),
                System.now(),
                UserInfo.getSessionId()
            ));
        }
        PublicApiOutboundTriggerService.enqueueStatusChanges(requests);
    }

    @TestVisible
    static Boolean didStatusChange(PublicApi_Submission__c newRecord, PublicApi_Submission__c oldRecord) {
        return normalizeStatus(newRecord.Status__c) != normalizeStatus(oldRecord.Status__c);
    }

    @TestVisible
    static Boolean shouldSendStatusUpdate(PublicApiConfigService.Config config, String status) {
        return PublicApiOutboundTriggerService.shouldSendStatusUpdate(config, status);
    }

    @TestVisible
    static Boolean isOutboundTriggerEnabled(PublicApiConfigService.Config config) {
        return PublicApiOutboundTriggerService.isOutboundTriggerEnabled(config);
    }

    @TestVisible
    static Set<String> getConfiguredTriggerStatuses(PublicApiConfigService.Config config) {
        return PublicApiOutboundTriggerService.getConfiguredTriggerStatuses(config);
    }

    @TestVisible
    static Set<String> parseTriggerStatuses(String rawValues) {
        return PublicApiOutboundTriggerService.parseTriggerStatuses(rawValues);
    }

    private static String normalizeStatus(String status) {
        return PublicApiOutboundTriggerService.normalizeStatus(status);
    }

}
