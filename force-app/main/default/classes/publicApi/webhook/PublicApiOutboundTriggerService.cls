public without sharing class PublicApiOutboundTriggerService {
    @TestVisible
    static final String DEFAULT_TRIGGER_FIELD_NAME = 'Processing_Status__c';
    @TestVisible
    static final String SUBMISSION_OBJECT_API_NAME = PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME;

    @TestVisible
    static final Set<String> DEFAULT_TRIGGER_FIELD_VALUES = new Set<String>{ 'Succeeded' };

    @TestVisible
    static Set<String> processedEventKeys = new Set<String>();

    public class ChangeRequest {
        public Id recordId;
        public Id configId;
        public String previousValue;
        public String currentValue;
        public Datetime changedAt;

        public ChangeRequest() {}

        public ChangeRequest(
            Id recordId,
            Id configId,
            String previousValue,
            String currentValue,
            Datetime changedAt
        ) {
            this.recordId = recordId;
            this.configId = configId;
            this.previousValue = previousValue;
            this.currentValue = currentValue;
            this.changedAt = changedAt;
        }
    }

    public static void enqueueFieldChanges(List<ChangeRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(getConfigIds(requests));
        Map<String, PublicApi_Submission__c> submissionsByResolutionKey =
            getSubmissionRecordsByResolutionKey(requests, configsById);
        if (configsById.isEmpty()) {
            return;
        }

        List<ChangeRequest> eventsToPublish = new List<ChangeRequest>();
        for (ChangeRequest request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(request.configId);
            if (config == null) {
                continue;
            }

            PublicApi_Submission__c submissionRecord = resolveSubmissionRecord(
                request,
                config,
                submissionsByResolutionKey
            );
            if (submissionRecord == null) {
                continue;
            }

            String normalizedCurrentValue = normalizeTriggerValue(request.currentValue);
            if (!shouldSendOutboundTrigger(config, normalizedCurrentValue)) {
                continue;
            }

            String eventKey = String.valueOf(request.recordId) + ':' +
                String.valueOf(request.configId) + ':' +
                normalizeTriggerValue(request.previousValue) + ':' +
                normalizedCurrentValue;
            if (processedEventKeys.contains(eventKey)) {
                continue;
            }
            processedEventKeys.add(eventKey);

            eventsToPublish.add(new ChangeRequest(
                submissionRecord.Id,
                request.configId,
                normalizeTriggerValue(request.previousValue),
                normalizedCurrentValue,
                request.changedAt == null ? System.now() : request.changedAt
            ));
        }

        if (!eventsToPublish.isEmpty()) {
            PublicApiOutboundRequestEventService.publishRequests(eventsToPublish);
        }
    }

    public static void enqueueStatusChanges(List<ChangeRequest> requests) {
        enqueueFieldChanges(requests);
    }

    @TestVisible
    public static Boolean shouldSendOutboundTrigger(PublicApiConfigService.Config config, String currentValue) {
        if (!isOutboundTriggerEnabled(config)) {
            return false;
        }
        if (String.isBlank(currentValue)) {
            return false;
        }
        return getConfiguredTriggerFieldValues(config).contains(currentValue);
    }

    @TestVisible
    public static Boolean shouldSendStatusUpdate(PublicApiConfigService.Config config, String status) {
        return shouldSendOutboundTrigger(config, status);
    }

    @TestVisible
    public static Boolean isOutboundTriggerEnabled(PublicApiConfigService.Config config) {
        if (config == null) {
            return false;
        }
        return config.outboundTriggerEnabled == null ? true : config.outboundTriggerEnabled;
    }

    @TestVisible
    public static String getConfiguredTriggerFieldName(PublicApiConfigService.Config config) {
        if (config == null || String.isBlank(config.outboundTriggerFieldName)) {
            if (config != null && config.targetObjectApiName != SUBMISSION_OBJECT_API_NAME) {
                return null;
            }
            return DEFAULT_TRIGGER_FIELD_NAME;
        }
        return config.outboundTriggerFieldName.trim();
    }

    @TestVisible
    public static Set<String> getConfiguredTriggerFieldValues(PublicApiConfigService.Config config) {
        if (config == null || String.isBlank(config.outboundTriggerFieldValues)) {
            if (config != null && config.targetObjectApiName != SUBMISSION_OBJECT_API_NAME) {
                return new Set<String>();
            }
            return new Set<String>(DEFAULT_TRIGGER_FIELD_VALUES);
        }
        Set<String> parsed = parseTriggerFieldValues(config.outboundTriggerFieldValues);
        if (!parsed.isEmpty()) {
            return parsed;
        }
        return config != null && config.targetObjectApiName != SUBMISSION_OBJECT_API_NAME
            ? new Set<String>()
            : new Set<String>(DEFAULT_TRIGGER_FIELD_VALUES);
    }

    @TestVisible
    public static Set<String> getConfiguredTriggerStatuses(PublicApiConfigService.Config config) {
        return getConfiguredTriggerFieldValues(config);
    }

    @TestVisible
    static Set<Id> getConfigIds(List<ChangeRequest> requests) {
        Set<Id> configIds = new Set<Id>();
        if (requests == null) {
            return configIds;
        }
        for (ChangeRequest request : requests) {
            if (request != null && request.configId != null) {
                configIds.add(request.configId);
            }
        }
        return configIds;
    }

    @TestVisible
    static Map<String, PublicApi_Submission__c> getSubmissionRecordsByResolutionKey(
        List<ChangeRequest> requests,
        Map<Id, PublicApiConfigService.Config> configsById
    ) {
        Map<String, PublicApi_Submission__c> submissionsByKey = new Map<String, PublicApi_Submission__c>();
        if (requests == null || requests.isEmpty() || configsById == null || configsById.isEmpty()) {
            return submissionsByKey;
        }

        Set<Id> configIds = new Set<Id>();
        Set<Id> submissionIds = new Set<Id>();
        Set<String> targetRecordIds = new Set<String>();
        for (ChangeRequest request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }
            configIds.add(request.configId);

            PublicApiConfigService.Config config = configsById.get(request.configId);
            if (config != null && config.targetObjectApiName == SUBMISSION_OBJECT_API_NAME) {
                submissionIds.add(request.recordId);
            } else {
                targetRecordIds.add(String.valueOf(request.recordId));
            }
        }
        if (configIds.isEmpty()) {
            return submissionsByKey;
        }

        for (PublicApi_Submission__c submissionRecord : [
            SELECT Id, PublicApi_Integration_Config__c, Target_Object_API_Name__c, Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE PublicApi_Integration_Config__c IN :configIds
            AND (Id IN :submissionIds OR Target_Record_Id__c IN :targetRecordIds)
        ]) {
            submissionsByKey.put(buildResolutionKey(submissionRecord.PublicApi_Integration_Config__c, submissionRecord.Id), submissionRecord);
            if (String.isNotBlank(submissionRecord.Target_Record_Id__c)) {
                submissionsByKey.put(
                    buildResolutionKey(submissionRecord.PublicApi_Integration_Config__c, submissionRecord.Target_Record_Id__c),
                    submissionRecord
                );
            }
        }
        return submissionsByKey;
    }

    @TestVisible
    static PublicApi_Submission__c resolveSubmissionRecord(
        ChangeRequest request,
        PublicApiConfigService.Config config,
        Map<String, PublicApi_Submission__c> submissionsByResolutionKey
    ) {
        if (request == null || request.recordId == null || request.configId == null) {
            return null;
        }
        if (config != null && config.targetObjectApiName == SUBMISSION_OBJECT_API_NAME) {
            return submissionsByResolutionKey.get(buildResolutionKey(request.configId, request.recordId));
        }
        return submissionsByResolutionKey.get(buildResolutionKey(request.configId, String.valueOf(request.recordId)));
    }

    @TestVisible
    public static String buildResolutionKey(Id configId, Object recordKey) {
        return String.valueOf(configId) + ':' + String.valueOf(recordKey);
    }

    @TestVisible
    public static Set<String> parseTriggerFieldValues(String rawValues) {
        Set<String> values = new Set<String>();
        if (String.isBlank(rawValues)) {
            return values;
        }

        String trimmed = rawValues.trim();
        if (trimmed.startsWith('[')) {
            try {
                Object parsed = JSON.deserializeUntyped(trimmed);
                if (parsed instanceof List<Object>) {
                    for (Object value : (List<Object>) parsed) {
                        String normalized = normalizeTriggerValue(value == null ? null : String.valueOf(value));
                        if (String.isNotBlank(normalized)) {
                            values.add(normalized);
                        }
                    }
                    return values;
                }
            } catch (Exception e) {
                // Fall through to delimiter parsing.
            }
        }

        String normalizedInput = trimmed.replace('\r', '\n').replace(';', ',');
        for (String token : normalizedInput.split('[,\\n]+')) {
            String normalized = normalizeTriggerValue(token);
            if (String.isNotBlank(normalized)) {
                values.add(normalized);
            }
        }
        return values;
    }

    @TestVisible
    public static Set<String> parseTriggerStatuses(String rawValues) {
        return parseTriggerFieldValues(rawValues);
    }

    @TestVisible
    public static String normalizeTriggerValue(String value) {
        return value == null ? null : value.trim();
    }

    @TestVisible
    public static String normalizeStatus(String status) {
        return normalizeTriggerValue(status);
    }
}
