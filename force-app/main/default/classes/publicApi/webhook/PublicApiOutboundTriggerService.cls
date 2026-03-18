public without sharing class PublicApiOutboundTriggerService {
    @TestVisible
    static final String DEFAULT_TRIGGER_FIELD_NAME = 'Processing_Status__c';

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

        Map<Id, Id> linkedConfigIdBySubmissionId = getLinkedConfigIdBySubmissionId(getSubmissionIds(requests));
        Set<Id> configIds = new Set<Id>();
        for (ChangeRequest request : requests) {
            if (request == null || request.recordId == null) {
                continue;
            }

            Id linkedConfigId = linkedConfigIdBySubmissionId.get(request.recordId);
            if (linkedConfigId == null) {
                continue;
            }
            if (request.configId != null && request.configId != linkedConfigId) {
                throw new PublicApiSubmissionServiceException(
                    'Outbound request config does not match the submission-linked Public API Integration Config.'
                );
            }
            configIds.add(linkedConfigId);
        }
        if (configIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(configIds);
        List<ChangeRequest> eventsToPublish = new List<ChangeRequest>();
        for (ChangeRequest request : requests) {
            if (request == null || request.recordId == null) {
                continue;
            }

            Id linkedConfigId = linkedConfigIdBySubmissionId.get(request.recordId);
            if (linkedConfigId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(linkedConfigId);
            String normalizedCurrentValue = normalizeTriggerValue(request.currentValue);
            if (!shouldSendOutboundTrigger(config, normalizedCurrentValue)) {
                continue;
            }

            String eventKey = String.valueOf(request.recordId) + ':' +
                String.valueOf(linkedConfigId) + ':' +
                normalizeTriggerValue(request.previousValue) + ':' +
                normalizedCurrentValue;
            if (processedEventKeys.contains(eventKey)) {
                continue;
            }
            processedEventKeys.add(eventKey);

            eventsToPublish.add(new ChangeRequest(
                request.recordId,
                linkedConfigId,
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
            return DEFAULT_TRIGGER_FIELD_NAME;
        }
        return config.outboundTriggerFieldName.trim();
    }

    @TestVisible
    public static Set<String> getConfiguredTriggerFieldValues(PublicApiConfigService.Config config) {
        if (config == null || String.isBlank(config.outboundTriggerFieldValues)) {
            return new Set<String>(DEFAULT_TRIGGER_FIELD_VALUES);
        }
        Set<String> parsed = parseTriggerFieldValues(config.outboundTriggerFieldValues);
        return parsed.isEmpty() ? new Set<String>(DEFAULT_TRIGGER_FIELD_VALUES) : parsed;
    }

    @TestVisible
    public static Set<String> getConfiguredTriggerStatuses(PublicApiConfigService.Config config) {
        return getConfiguredTriggerFieldValues(config);
    }

    @TestVisible
    static Set<Id> getSubmissionIds(List<ChangeRequest> requests) {
        Set<Id> submissionIds = new Set<Id>();
        if (requests == null) {
            return submissionIds;
        }
        for (ChangeRequest request : requests) {
            if (request != null && request.recordId != null) {
                submissionIds.add(request.recordId);
            }
        }
        return submissionIds;
    }

    @TestVisible
    static Map<Id, Id> getLinkedConfigIdBySubmissionId(Set<Id> submissionIds) {
        Map<Id, Id> linkedConfigIdBySubmissionId = new Map<Id, Id>();
        if (submissionIds == null || submissionIds.isEmpty()) {
            return linkedConfigIdBySubmissionId;
        }
        for (PublicApi_Submission__c submissionRecord : [
            SELECT Id, PublicApi_Integration_Config__c
            FROM PublicApi_Submission__c
            WHERE Id IN :submissionIds
        ]) {
            linkedConfigIdBySubmissionId.put(submissionRecord.Id, submissionRecord.PublicApi_Integration_Config__c);
        }
        return linkedConfigIdBySubmissionId;
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
