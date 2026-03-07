public without sharing class PublicApiStatusUpdateHandler {
    @TestVisible
    static final Set<String> NOTIFIABLE_STATUSES = new Set<String>{ 'Referred Out', 'Converted' };

    private static Set<String> processedEventKeys = new Set<String>();
    private static Set<Id> processedRecordIds = new Set<Id>();

    public static void handleBeforeUpdate(List<PublicApi_Submission__c> newRecords, Map<Id, PublicApi_Submission__c> oldMap) {
        if (newRecords == null || newRecords.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> candidateIds = new Set<Id>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord == null || !didStatusChange(newRecord, oldRecord)) {
                continue;
            }
            String currentStatus = normalizeStatus(newRecord.Status__c);
            if (!shouldSendStatusUpdate(currentStatus)) {
                continue;
            }
            candidateIds.add(newRecord.Id);
        }
        if (candidateIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApi_Intake_Tracking__c> trackingByRecordId =
            PublicApiIntakeTrackingService.getTrackingByIntakeId(candidateIds);
        if (trackingByRecordId.isEmpty()) {
            return;
        }

        for (PublicApi_Submission__c newRecord : newRecords) {
            if (!candidateIds.contains(newRecord.Id) || !trackingByRecordId.containsKey(newRecord.Id)) {
                continue;
            }
            if (Schema.sObjectType.PublicApi_Submission__c.fields.Google_Ads_Conversion_Event__c != null) {
                newRecord.Google_Ads_Conversion_Event__c = normalizeStatus(newRecord.Status__c);
            }
            if (Schema.sObjectType.PublicApi_Submission__c.fields.Google_Ads_Conversion_Time__c != null) {
                newRecord.Google_Ads_Conversion_Time__c = System.now();
            }
        }
    }

    public static void handleAfterUpdate(List<PublicApi_Submission__c> newRecords, Map<Id, PublicApi_Submission__c> oldMap) {
        if (newRecords == null || newRecords.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> changedIds = new Set<Id>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord != null && didStatusChange(newRecord, oldRecord)) {
                if (shouldSendStatusUpdate(normalizeStatus(newRecord.Status__c))) {
                    changedIds.add(newRecord.Id);
                }
            }
        }
        if (changedIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApi_Intake_Tracking__c> trackingByRecordId =
            PublicApiIntakeTrackingService.getTrackingByIntakeId(changedIds);
        if (trackingByRecordId.isEmpty()) {
            return;
        }

        List<PublicApiStatusUpdateQueueable.DeliveryItem> items = new List<PublicApiStatusUpdateQueueable.DeliveryItem>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord == null || !didStatusChange(newRecord, oldRecord)) {
                continue;
            }
            String currentStatus = normalizeStatus(newRecord.Status__c);
            if (!shouldSendStatusUpdate(currentStatus)) {
                continue;
            }

            PublicApi_Intake_Tracking__c tracking = trackingByRecordId.get(newRecord.Id);
            if (tracking == null || tracking.PublicApi_Integration_Config__c == null) {
                continue;
            }
            if (processedRecordIds.contains(newRecord.Id)) {
                continue;
            }

            String eventKey = String.valueOf(newRecord.Id) + ':' + normalizeStatus(oldRecord.Status__c) + ':' + currentStatus;
            if (processedEventKeys.contains(eventKey)) {
                continue;
            }
            processedEventKeys.add(eventKey);
            processedRecordIds.add(newRecord.Id);

            items.add(new PublicApiStatusUpdateQueueable.DeliveryItem(
                newRecord.Id,
                tracking.PublicApi_Integration_Config__c,
                normalizeStatus(oldRecord.Status__c),
                currentStatus,
                System.now(),
                UserInfo.getSessionId()
            ));
        }

        if (!items.isEmpty()) {
            PublicApiStatusUpdateQueueable.enqueue(items);
        }
    }

    @TestVisible
    static Boolean didStatusChange(PublicApi_Submission__c newRecord, PublicApi_Submission__c oldRecord) {
        return normalizeStatus(newRecord.Status__c) != normalizeStatus(oldRecord.Status__c);
    }

    @TestVisible
    static Boolean shouldSendStatusUpdate(String status) {
        return String.isNotBlank(status) && NOTIFIABLE_STATUSES.contains(status);
    }

    private static String normalizeStatus(String status) {
        return status == null ? null : status.trim();
    }
}
