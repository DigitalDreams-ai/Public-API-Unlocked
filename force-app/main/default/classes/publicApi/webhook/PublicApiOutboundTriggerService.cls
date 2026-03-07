public without sharing class PublicApiOutboundTriggerService {
    @TestVisible
    static final Set<String> DEFAULT_TRIGGER_STATUSES = new Set<String>{ 'Referred Out', 'Converted' };

    @TestVisible
    static Set<String> processedEventKeys = new Set<String>();

    public class StatusChangeRequest {
        public Id recordId;
        public Id configId;
        public String previousStatus;
        public String currentStatus;
        public Datetime changedAt;
        public String sessionId;

        public StatusChangeRequest() {}

        public StatusChangeRequest(
            Id recordId,
            Id configId,
            String previousStatus,
            String currentStatus,
            Datetime changedAt,
            String sessionId
        ) {
            this.recordId = recordId;
            this.configId = configId;
            this.previousStatus = previousStatus;
            this.currentStatus = currentStatus;
            this.changedAt = changedAt;
            this.sessionId = sessionId;
        }
    }

    public static void enqueueStatusChanges(List<StatusChangeRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> configIds = new Set<Id>();
        for (StatusChangeRequest request : requests) {
            if (request != null && request.configId != null) {
                configIds.add(request.configId);
            }
        }
        if (configIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(configIds);
        List<PublicApiStatusUpdateQueueable.DeliveryItem> items = new List<PublicApiStatusUpdateQueueable.DeliveryItem>();
        for (StatusChangeRequest request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(request.configId);
            String normalizedCurrentStatus = normalizeStatus(request.currentStatus);
            if (!shouldSendStatusUpdate(config, normalizedCurrentStatus)) {
                continue;
            }

            String eventKey = String.valueOf(request.recordId) + ':' +
                String.valueOf(request.configId) + ':' +
                normalizeStatus(request.previousStatus) + ':' +
                normalizedCurrentStatus;
            if (processedEventKeys.contains(eventKey)) {
                continue;
            }
            processedEventKeys.add(eventKey);

            items.add(new PublicApiStatusUpdateQueueable.DeliveryItem(
                request.recordId,
                request.configId,
                normalizeStatus(request.previousStatus),
                normalizedCurrentStatus,
                request.changedAt == null ? System.now() : request.changedAt,
                request.sessionId
            ));
        }

        if (!items.isEmpty()) {
            PublicApiStatusUpdateQueueable.enqueue(items);
        }
    }

    @TestVisible
    public static Boolean shouldSendStatusUpdate(PublicApiConfigService.Config config, String status) {
        if (!isOutboundTriggerEnabled(config)) {
            return false;
        }
        if (String.isBlank(status)) {
            return false;
        }
        return getConfiguredTriggerStatuses(config).contains(status);
    }

    @TestVisible
    public static Boolean isOutboundTriggerEnabled(PublicApiConfigService.Config config) {
        if (config == null) {
            return false;
        }
        return config.outboundTriggerEnabled == null ? true : config.outboundTriggerEnabled;
    }

    @TestVisible
    public static Set<String> getConfiguredTriggerStatuses(PublicApiConfigService.Config config) {
        if (config == null || String.isBlank(config.outboundTriggerStatusValues)) {
            return new Set<String>(DEFAULT_TRIGGER_STATUSES);
        }
        Set<String> parsed = parseTriggerStatuses(config.outboundTriggerStatusValues);
        return parsed.isEmpty() ? new Set<String>(DEFAULT_TRIGGER_STATUSES) : parsed;
    }

    @TestVisible
    public static Set<String> parseTriggerStatuses(String rawValues) {
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

    @TestVisible
    public static String normalizeStatus(String status) {
        return status == null ? null : status.trim();
    }
}
