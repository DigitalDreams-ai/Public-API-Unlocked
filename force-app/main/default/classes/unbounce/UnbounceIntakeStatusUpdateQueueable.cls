/**
 * Sends outbound webhook notifications when a Unbounce-created Intake changes status.
 */
public without sharing class UnbounceIntakeStatusUpdateQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final Integer MAX_DELIVERIES_PER_JOB = 90;
    @TestVisible
    private static final String DEFAULT_CONTENT_TYPE = 'application/json';
    @TestVisible
    private static final String DEFAULT_API_KEY_HEADER = 'X-API-KEY';
    @TestVisible
    private static final String DEFAULT_AUTHORIZATION_HEADER = 'Authorization';
    @TestVisible
    private static final String DEFAULT_SIGNATURE_HEADER = 'x-unbounce-signature';
    @TestVisible
    private static final String AUTH_MODE_NONE = 'None';
    @TestVisible
    private static final String AUTH_MODE_API_KEY_HEADER = 'ApiKeyHeader';
    @TestVisible
    private static final String AUTH_MODE_BEARER_TOKEN = 'BearerToken';
    @TestVisible
    private static final String AUTH_MODE_BASIC_AUTH = 'BasicAuth';
    @TestVisible
    private static final String AUTH_MODE_HMAC_SIGNATURE = 'HmacSignature';

    public class DeliveryItem {
        public Id intakeId;
        public Id configId;
        public String previousStatus;
        public String currentStatus;
        public Datetime changedAt;

        public DeliveryItem(Id intakeId, Id configId, String previousStatus, String currentStatus, Datetime changedAt) {
            this.intakeId = intakeId;
            this.configId = configId;
            this.previousStatus = previousStatus;
            this.currentStatus = currentStatus;
            this.changedAt = changedAt;
        }
    }

    private List<String> serializedItems;

    public UnbounceIntakeStatusUpdateQueueable(List<String> serializedItems) {
        this.serializedItems = serializedItems != null ? serializedItems : new List<String>();
    }

    public static void enqueue(List<DeliveryItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        List<String> serialized = new List<String>();
        for (DeliveryItem item : items) {
            serialized.add(JSON.serialize(item));
        }
        System.enqueueJob(new UnbounceIntakeStatusUpdateQueueable(serialized));
    }

    public void execute(QueueableContext context) {
        if (serializedItems == null || serializedItems.isEmpty()) {
            return;
        }

        List<String> currentBatchSerialized = takeBatch(serializedItems);
        List<String> remainingSerialized = dropBatch(serializedItems);
        List<DeliveryItem> items = deserializeItems(currentBatchSerialized);
        if (items.isEmpty()) {
            enqueueSerializedItems(remainingSerialized);
            return;
        }

        Map<Id, UnbounceConfigService.Config> configsById = resolveConfigsById(items);
        Map<Id, litify_pm__Intake__c> intakesById = queryIntakes(items, configsById);
        Http http = new Http();
        List<Unbounce_Webhook_Delivery__c> deliveryRecords = new List<Unbounce_Webhook_Delivery__c>();
        Map<Id, Unbounce_Integration_Config__c> summaryUpdatesByConfig =
            new Map<Id, Unbounce_Integration_Config__c>();

        for (DeliveryItem item : items) {
            litify_pm__Intake__c intake = intakesById.get(item.intakeId);
            if (intake == null || item == null || item.configId == null) {
                continue;
            }
            UnbounceConfigService.Config config = configsById.get(item.configId);
            if (config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
                continue;
            }

            String payload = null;
            UnbounceWebhookDeliveryRecordService.DeliveryResult result = null;

            try {
                Map<String, Object> payloadMap = buildPayload(intake, item, config);
                payload = JSON.serialize(payloadMap);
                HttpRequest request = new HttpRequest();
                request.setMethod('POST');
                request.setEndpoint(config.statusUpdateWebhookUrl);
                request.setBody(payload);
                applyRequestConfiguration(request, config, payload);
                HttpResponse response = http.send(request);
                result =
                    buildDeliveryResult(
                        response.getStatusCode() >= 200 && response.getStatusCode() < 300,
                        response.getStatusCode(),
                        response.getBody(),
                        response.getStatus()
                    );

                if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Unbounce intake status webhook failed for Intake ' + intake.Id +
                        ' with status code ' + response.getStatusCode() +
                        ' and body ' + response.getBody()
                    );
                }
            } catch (Exception e) {
                result =
                    buildDeliveryResult(false, null, null, null, e.getMessage());
                System.debug(
                    LoggingLevel.WARN,
                    'Unbounce intake status webhook callout failed for Intake ' + intake.Id + ': ' + e.getMessage()
                );
            }

            Unbounce_Webhook_Delivery__c deliveryRecord =
                UnbounceWebhookDeliveryRecordService.buildDeliveryRecord(
                    item.configId,
                    intake.Id,
                    item.currentStatus,
                    config.statusUpdateWebhookUrl,
                    payload,
                    result
                );
            if (deliveryRecord != null) {
                deliveryRecords.add(deliveryRecord);
                UnbounceWebhookDeliveryRecordService.mergeLatestDeliverySummary(
                    summaryUpdatesByConfig,
                    deliveryRecord
                );
            }
        }

        UnbounceWebhookDeliveryRecordService.persistDeliveryResults(
            deliveryRecords,
            summaryUpdatesByConfig
        );
        enqueueSerializedItems(remainingSerialized);
    }

    @TestVisible
    private static List<DeliveryItem> deserializeItems(List<String> serializedItems) {
        List<DeliveryItem> items = new List<DeliveryItem>();
        for (String serialized : serializedItems) {
            if (String.isBlank(serialized)) {
                continue;
            }
            items.add((DeliveryItem) JSON.deserialize(serialized, DeliveryItem.class));
        }
        return items;
    }

    @TestVisible
    private static Map<String, Object> buildPayload(
        litify_pm__Intake__c intake,
        DeliveryItem item,
        UnbounceConfigService.Config config
    ) {
        return UnbounceRequestMappingService.buildOutboundPayload(
            intake,
            config == null ? null : config.requestFieldMappingsConfiguration,
            UnbounceRequestMappingService.getDefaultDirection()
        );
    }

    @TestVisible
    private static void applyRequestConfiguration(
        HttpRequest request,
        UnbounceConfigService.Config config,
        String payload
    ) {
        request.setHeader('Content-Type', getContentType(config));
        request.setHeader('X-Unbounce-Event-Type', 'status_changed');
        applyAuthHeaders(request, config, payload);
        applyAdditionalHeaders(request, config);
    }

    @TestVisible
    private static String getContentType(UnbounceConfigService.Config config) {
        String configuredContentType = config == null ? null : config.outboundContentType;
        return String.isBlank(configuredContentType) ? DEFAULT_CONTENT_TYPE : configuredContentType.trim();
    }

    @TestVisible
    private static void applyAuthHeaders(
        HttpRequest request,
        UnbounceConfigService.Config config,
        String payload
    ) {
        if (request == null || config == null) {
            return;
        }

        String authMode = normalizeConfigValue(config.outboundAuthMode);
        if (String.isBlank(authMode)) {
            applyLegacySignature(request, config, payload);
            return;
        }
        if (authMode == AUTH_MODE_NONE) {
            return;
        }
        if (authMode == AUTH_MODE_API_KEY_HEADER) {
            String headerValue = normalizeConfigValue(config.outboundHeaderValue);
            if (String.isNotBlank(headerValue)) {
                request.setHeader(getApiKeyHeaderName(config), headerValue);
            }
            return;
        }
        if (authMode == AUTH_MODE_BEARER_TOKEN) {
            String token = normalizeConfigValue(config.outboundHeaderValue);
            if (String.isNotBlank(token)) {
                request.setHeader(getAuthorizationHeaderName(config), 'Bearer ' + token);
            }
            return;
        }
        if (authMode == AUTH_MODE_BASIC_AUTH) {
            String sourceValue = normalizeConfigValue(config.outboundHeaderValue);
            if (String.isNotBlank(sourceValue)) {
                request.setHeader(
                    getAuthorizationHeaderName(config),
                    'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(sourceValue))
                );
            }
            return;
        }
        if (authMode == AUTH_MODE_HMAC_SIGNATURE) {
            applySignatureHeader(request, config, payload);
        }
    }

    @TestVisible
    private static void applyAdditionalHeaders(HttpRequest request, UnbounceConfigService.Config config) {
        if (request == null || config == null || String.isBlank(config.outboundAdditionalHeadersJson)) {
            return;
        }

        Object parsedHeaders = JSON.deserializeUntyped(config.outboundAdditionalHeadersJson);
        if (parsedHeaders instanceof Map<String, Object>) {
            Map<String, Object> headers = (Map<String, Object>) parsedHeaders;
            for (String headerName : headers.keySet()) {
                String headerValue = stringifyHeaderValue(headers.get(headerName));
                if (String.isNotBlank(headerName) &&
                    headerValue != null &&
                    !isManagedHeaderName(headerName, config)) {
                    request.setHeader(headerName, headerValue);
                }
            }
            return;
        }
        if (parsedHeaders instanceof List<Object>) {
            for (Object entry : (List<Object>) parsedHeaders) {
                if (!(entry instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> headerConfig = (Map<String, Object>) entry;
                String headerName = firstNonBlank(
                    stringifyHeaderValue(headerConfig.get('name')),
                    stringifyHeaderValue(headerConfig.get('header'))
                );
                String headerValue = stringifyHeaderValue(headerConfig.get('value'));
                if (String.isNotBlank(headerName) &&
                    headerValue != null &&
                    !isManagedHeaderName(headerName, config)) {
                    request.setHeader(headerName, headerValue);
                }
            }
        }
    }

    @TestVisible
    private static List<String> takeBatch(List<String> sourceItems) {
        List<String> batch = new List<String>();
        if (sourceItems == null || sourceItems.isEmpty()) {
            return batch;
        }

        Integer limitSize = Math.min(MAX_DELIVERIES_PER_JOB, sourceItems.size());
        for (Integer index = 0; index < limitSize; index++) {
            batch.add(sourceItems[index]);
        }
        return batch;
    }

    @TestVisible
    private static List<String> dropBatch(List<String> sourceItems) {
        List<String> remaining = new List<String>();
        if (sourceItems == null || sourceItems.size() <= MAX_DELIVERIES_PER_JOB) {
            return remaining;
        }

        for (Integer index = MAX_DELIVERIES_PER_JOB; index < sourceItems.size(); index++) {
            remaining.add(sourceItems[index]);
        }
        return remaining;
    }

    private static void enqueueSerializedItems(List<String> remainingSerialized) {
        if (remainingSerialized == null || remainingSerialized.isEmpty()) {
            return;
        }
        System.enqueueJob(new UnbounceIntakeStatusUpdateQueueable(remainingSerialized));
    }

    private static Map<Id, litify_pm__Intake__c> queryIntakes(
        List<DeliveryItem> items,
        Map<Id, UnbounceConfigService.Config> configsById
    ) {
        Set<Id> intakeIds = new Set<Id>();
        for (DeliveryItem item : items) {
            if (item != null && item.intakeId != null) {
                intakeIds.add(item.intakeId);
            }
        }
        if (intakeIds.isEmpty()) {
            return new Map<Id, litify_pm__Intake__c>();
        }

        Set<String> selectedFields = new Set<String>{ 'Id' };
        for (UnbounceConfigService.Config config : configsById.values()) {
            selectedFields.addAll(
                UnbounceRequestMappingService.getOutboundFieldApiNames(
                    config == null ? null : config.requestFieldMappingsConfiguration,
                    UnbounceRequestMappingService.getDefaultDirection()
                )
            );
        }

        List<litify_pm__Intake__c> queriedIntakes =
            (List<litify_pm__Intake__c>) Database.query(
                'SELECT ' + String.join(new List<String>(selectedFields), ', ') +
                ' FROM litify_pm__Intake__c WHERE Id IN :intakeIds'
            );
        return new Map<Id, litify_pm__Intake__c>(queriedIntakes);
    }

    private static Map<Id, UnbounceConfigService.Config> resolveConfigsById(List<DeliveryItem> items) {
        Set<Id> configIds = new Set<Id>();
        for (DeliveryItem item : items) {
            Id configId = item != null ? item.configId : null;
            if (configId != null) {
                configIds.add(configId);
            }
        }
        return UnbounceConfigService.getConfigsById(configIds);
    }

    private static Set<Id> getConfigIds(List<DeliveryItem> items) {
        Set<Id> configIds = new Set<Id>();
        if (items == null) {
            return configIds;
        }
        for (DeliveryItem item : items) {
            if (item != null && item.configId != null) {
                configIds.add(item.configId);
            }
        }
        return configIds;
    }

    @TestVisible
    private static UnbounceWebhookDeliveryRecordService.DeliveryResult buildDeliveryResult(
        Boolean success,
        Integer statusCode,
        String responseBody,
        String message
    ) {
        return buildDeliveryResult(success, statusCode, responseBody, message, null);
    }

    @TestVisible
    private static UnbounceWebhookDeliveryRecordService.DeliveryResult buildDeliveryResult(
        Boolean success,
        Integer statusCode,
        String responseBody,
        String message,
        String exceptionMessage
    ) {
        UnbounceWebhookDeliveryRecordService.DeliveryResult result =
            new UnbounceWebhookDeliveryRecordService.DeliveryResult();
        result.success = success;
        result.statusCode = statusCode;
        result.responseBody = responseBody;
        result.message = message;
        result.exceptionMessage = exceptionMessage;
        return result;
    }

    private static String formatAsIso8601(Datetime value) {
        return value == null ? null : value.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }

    private static void applyLegacySignature(
        HttpRequest request,
        UnbounceConfigService.Config config,
        String payload
    ) {
        if (String.isBlank(config.statusUpdateWebhookSecret)) {
            return;
        }
        String signature = UnbounceClient.generateWebhookSignature(payload, config.statusUpdateWebhookSecret);
        if (String.isNotBlank(signature)) {
            request.setHeader(DEFAULT_SIGNATURE_HEADER, signature);
        }
    }

    private static void applySignatureHeader(
        HttpRequest request,
        UnbounceConfigService.Config config,
        String payload
    ) {
        if (String.isBlank(config.statusUpdateWebhookSecret)) {
            return;
        }
        String signature = UnbounceClient.generateWebhookSignature(payload, config.statusUpdateWebhookSecret);
        if (String.isBlank(signature)) {
            return;
        }
        request.setHeader(getSignatureHeaderName(config), signature);
    }

    private static String getApiKeyHeaderName(UnbounceConfigService.Config config) {
        return firstNonBlank(normalizeConfigValue(config.outboundHeaderName), DEFAULT_API_KEY_HEADER);
    }

    private static String getAuthorizationHeaderName(UnbounceConfigService.Config config) {
        return firstNonBlank(normalizeConfigValue(config.outboundHeaderName), DEFAULT_AUTHORIZATION_HEADER);
    }

    private static String getSignatureHeaderName(UnbounceConfigService.Config config) {
        return firstNonBlank(normalizeConfigValue(config.outboundHeaderName), DEFAULT_SIGNATURE_HEADER);
    }

    private static String normalizeConfigValue(String value) {
        return value == null ? null : value.trim();
    }

    private static String firstNonBlank(String primaryValue, String fallbackValue) {
        return String.isNotBlank(primaryValue) ? primaryValue : fallbackValue;
    }

    private static String stringifyHeaderValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean || value instanceof Decimal || value instanceof Integer || value instanceof Long) {
            return String.valueOf(value);
        }
        String stringValue = String.valueOf(value);
        return stringValue == null ? null : stringValue.trim();
    }

    @TestVisible
    private static Boolean isManagedHeaderName(String headerName, UnbounceConfigService.Config config) {
        String normalizedHeaderName = normalizeConfigValue(headerName);
        if (String.isBlank(normalizedHeaderName)) {
            return false;
        }

        String lowerHeaderName = normalizedHeaderName.toLowerCase();
        if (lowerHeaderName == 'content-type' || lowerHeaderName == 'x-unbounce-event-type') {
            return true;
        }

        String authMode = normalizeConfigValue(config == null ? null : config.outboundAuthMode);
        if (String.isBlank(authMode)) {
            return lowerHeaderName == DEFAULT_SIGNATURE_HEADER.toLowerCase();
        }
        if (authMode == AUTH_MODE_API_KEY_HEADER) {
            return lowerHeaderName == getApiKeyHeaderName(config).toLowerCase();
        }
        if (authMode == AUTH_MODE_BEARER_TOKEN || authMode == AUTH_MODE_BASIC_AUTH) {
            return lowerHeaderName == getAuthorizationHeaderName(config).toLowerCase();
        }
        if (authMode == AUTH_MODE_HMAC_SIGNATURE) {
            return lowerHeaderName == getSignatureHeaderName(config).toLowerCase();
        }
        return false;
    }
}
