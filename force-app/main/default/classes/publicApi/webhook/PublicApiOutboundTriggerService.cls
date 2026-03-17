public without sharing class PublicApiOutboundTriggerService {
    @TestVisible
    static final String DEFAULT_TRIGGER_FIELD_NAME = 'Status__c';

    @TestVisible
    static final Set<String> DEFAULT_TRIGGER_FIELD_VALUES = new Set<String>{ 'Referred Out', 'Converted' };

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

        Set<Id> configIds = new Set<Id>();
        for (ChangeRequest request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }
            configIds.add(request.configId);
        }
        if (configIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(configIds);
        List<ChangeRequest> eventsToPublish = new List<ChangeRequest>();
        for (ChangeRequest request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(request.configId);
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
                request.recordId,
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
