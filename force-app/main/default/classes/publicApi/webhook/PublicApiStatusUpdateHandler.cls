public without sharing class PublicApiStatusUpdateHandler {
    @TestVisible
    static final Set<String> DEFAULT_TRIGGER_STATUSES = new Set<String>{ 'Referred Out', 'Converted' };

    private static Set<String> processedEventKeys = new Set<String>();
    private static Set<Id> processedRecordIds = new Set<Id>();

    public static void handleBeforeUpdate(List<PublicApi_Submission__c> newRecords, Map<Id, PublicApi_Submission__c> oldMap) {
        // No before-update mutations are required for submission audit mode.
        return;
    }

    public static void handleAfterUpdate(List<PublicApi_Submission__c> newRecords, Map<Id, PublicApi_Submission__c> oldMap) {
        if (newRecords == null || newRecords.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> configIds = new Set<Id>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord != null && didStatusChange(newRecord, oldRecord) && newRecord.PublicApi_Integration_Config__c != null) {
                configIds.add(newRecord.PublicApi_Integration_Config__c);
            }
        }
        if (configIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(configIds);

        List<PublicApiStatusUpdateQueueable.DeliveryItem> items = new List<PublicApiStatusUpdateQueueable.DeliveryItem>();
        for (PublicApi_Submission__c newRecord : newRecords) {
            PublicApi_Submission__c oldRecord = oldMap.get(newRecord.Id);
            if (oldRecord == null || !didStatusChange(newRecord, oldRecord)) {
                continue;
            }
            if (newRecord.PublicApi_Integration_Config__c == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(newRecord.PublicApi_Integration_Config__c);
            String currentStatus = normalizeStatus(newRecord.Status__c);
            if (!shouldSendStatusUpdate(config, currentStatus)) {
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
                newRecord.PublicApi_Integration_Config__c,
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
    static Boolean shouldSendStatusUpdate(PublicApiConfigService.Config config, String status) {
        if (!isOutboundTriggerEnabled(config)) {
            return false;
        }
        if (String.isBlank(status)) {
            return false;
        }
        return getConfiguredTriggerStatuses(config).contains(status);
    }

    @TestVisible
    static Boolean isOutboundTriggerEnabled(PublicApiConfigService.Config config) {
        if (config == null) {
            return false;
        }
        return config.outboundTriggerEnabled == null ? true : config.outboundTriggerEnabled;
    }

    @TestVisible
    static Set<String> getConfiguredTriggerStatuses(PublicApiConfigService.Config config) {
        if (config == null || String.isBlank(config.outboundTriggerStatusValues)) {
            return new Set<String>(DEFAULT_TRIGGER_STATUSES);
        }
        Set<String> parsed = parseTriggerStatuses(config.outboundTriggerStatusValues);
        return parsed.isEmpty() ? new Set<String>(DEFAULT_TRIGGER_STATUSES) : parsed;
    }

    @TestVisible
    static Set<String> parseTriggerStatuses(String rawValues) {
        Set<String> statuses = new Set<String>();
        if (String.isBlank(rawValues)) {
            return statuses;
        }

        String trimmed = rawValues.trim();
        if (trimmed.startsWith('[')) {
            try {
                Object parsed = JSON.deserializeUntyped(trimmed);
                if (parsed instanceof List<Object>) {
                    for (Object value : (List<Object>) parsed) {
                        String normalized = normalizeStatus(value == null ? null : String.valueOf(value));
                        if (String.isNotBlank(normalized)) {
                            statuses.add(normalized);
                        }
                    }
                    return statuses;
                }
            } catch (Exception e) {
                // Fall through to delimiter parsing.
            }
        }

        String normalizedInput = trimmed.replace('\r', '\n').replace(';', ',');
        for (String token : normalizedInput.split('[,\\n]+')) {
            String normalized = normalizeStatus(token);
            if (String.isNotBlank(normalized)) {
                statuses.add(normalized);
            }
        }
        return statuses;
    }

    private static String normalizeStatus(String status) {
        return status == null ? null : status.trim();
    }

}
