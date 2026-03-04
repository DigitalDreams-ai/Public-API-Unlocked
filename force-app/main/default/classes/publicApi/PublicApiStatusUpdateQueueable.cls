public without sharing class PublicApiStatusUpdateQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible static final Integer MAX_DELIVERIES_PER_JOB = 90;
    @TestVisible static final String DEFAULT_CONTENT_TYPE = 'application/json';
    @TestVisible static final String DEFAULT_API_KEY_HEADER = 'X-API-KEY';
    @TestVisible static final String DEFAULT_AUTHORIZATION_HEADER = 'Authorization';
    @TestVisible static final String DEFAULT_SIGNATURE_HEADER = 'x-publicapi-signature';
    @TestVisible static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';

    @TestVisible static final String AUTH_MODE_NONE = 'None';
    @TestVisible static final String AUTH_MODE_API_KEY_HEADER = 'ApiKeyHeader';
    @TestVisible static final String AUTH_MODE_BEARER_TOKEN = 'BearerToken';
    @TestVisible static final String AUTH_MODE_BASIC_AUTH = 'BasicAuth';
    @TestVisible static final String AUTH_MODE_HMAC_SIGNATURE = 'HmacSignature';

    public class DeliveryItem {
        public Id recordId;
        public Id configId;
        public String previousStatus;
        public String currentStatus;
        public Datetime changedAt;

        public DeliveryItem() {}

        public DeliveryItem(Id recordId, Id configId, String previousStatus, String currentStatus, Datetime changedAt) {
            this.recordId = recordId;
            this.configId = configId;
            this.previousStatus = previousStatus;
            this.currentStatus = currentStatus;
            this.changedAt = changedAt;
        }
    }

    private List<String> serializedItems;

    public PublicApiStatusUpdateQueueable(List<String> serializedItems) {
        this.serializedItems = serializedItems == null ? new List<String>() : serializedItems;
    }

    public static void enqueue(List<DeliveryItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        List<String> serialized = new List<String>();
        for (DeliveryItem item : items) {
            serialized.add(JSON.serialize(item));
        }
        System.enqueueJob(new PublicApiStatusUpdateQueueable(serialized));
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

        Map<Id, PublicApiConfigService.Config> configsById = resolveConfigsById(items);
        Map<Id, SObject> recordsById = queryRecords(items, configsById);
        Http http = new Http();

        List<PublicApi_Webhook_Delivery__c> deliveryRecords = new List<PublicApi_Webhook_Delivery__c>();
        Map<Id, PublicApi_Integration_Config__c> summaryUpdatesByConfig = new Map<Id, PublicApi_Integration_Config__c>();

        for (DeliveryItem item : items) {
            if (item == null || item.recordId == null || item.configId == null) {
                continue;
            }
            SObject record = recordsById.get(item.recordId);
            PublicApiConfigService.Config config = configsById.get(item.configId);
            if (record == null || config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
                continue;
            }

            String payload = null;
            PublicApiWebhookDeliveryRecordService.DeliveryResult result = null;
            try {
                Map<String, Object> payloadMap = PublicApiRequestMappingService.buildOutboundPayload(
                    record,
                    config.requestFieldMappingsConfiguration,
                    PublicApiRequestMappingService.getDefaultDirection()
                );
                payload = JSON.serialize(payloadMap);

                HttpRequest request = new HttpRequest();
                request.setMethod('POST');
                request.setEndpoint(config.statusUpdateWebhookUrl);
                request.setBody(payload);
                applyRequestConfiguration(request, config, payload);

                HttpResponse response = http.send(request);
                result = buildDeliveryResult(
                    response.getStatusCode() >= 200 && response.getStatusCode() < 300,
                    response.getStatusCode(),
                    response.getBody(),
                    response.getStatus(),
                    null
                );
            } catch (Exception e) {
                result = buildDeliveryResult(false, null, null, null, e.getMessage());
            }

            PublicApi_Webhook_Delivery__c deliveryRecord = PublicApiWebhookDeliveryRecordService.buildDeliveryRecord(
                item.configId,
                item.recordId,
                item.currentStatus,
                config.statusUpdateWebhookUrl,
                payload,
                result
            );
            if (deliveryRecord != null) {
                deliveryRecords.add(deliveryRecord);
                PublicApiWebhookDeliveryRecordService.mergeLatestDeliverySummary(summaryUpdatesByConfig, deliveryRecord);
            }
        }

        PublicApiWebhookDeliveryRecordService.persistDeliveryResults(deliveryRecords, summaryUpdatesByConfig);
        enqueueSerializedItems(remainingSerialized);
    }

    @TestVisible
    static List<DeliveryItem> deserializeItems(List<String> serializedItems) {
        List<DeliveryItem> items = new List<DeliveryItem>();
        for (String serialized : serializedItems) {
            if (String.isBlank(serialized)) {
                continue;
            }
            try {
                items.add((DeliveryItem) JSON.deserialize(serialized, DeliveryItem.class));
            } catch (Exception e) {
                continue;
            }
        }
        return items;
    }

    @TestVisible
    static void applyRequestConfiguration(HttpRequest request, PublicApiConfigService.Config config, String payload) {
        request.setHeader('Content-Type', getContentType(config));
        request.setHeader('X-PublicApi-Event-Type', 'status_changed');
        applyAuthHeaders(request, config, payload);
        applyAdditionalHeaders(request, config);
    }

    @TestVisible
    static String getContentType(PublicApiConfigService.Config config) {
        String configured = config == null ? null : normalizeConfigValue(config.outboundContentType);
        return String.isBlank(configured) ? DEFAULT_CONTENT_TYPE : configured;
    }

    @TestVisible
    static void applyAuthHeaders(HttpRequest request, PublicApiConfigService.Config config, String payload) {
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
    static void applyAdditionalHeaders(HttpRequest request, PublicApiConfigService.Config config) {
        if (request == null || config == null || String.isBlank(config.outboundAdditionalHeadersJson)) {
            return;
        }

        Object parsedHeaders = JSON.deserializeUntyped(config.outboundAdditionalHeadersJson);
        if (parsedHeaders instanceof Map<String, Object>) {
            Map<String, Object> headers = (Map<String, Object>) parsedHeaders;
            for (String headerName : headers.keySet()) {
                String headerValue = stringifyHeaderValue(headers.get(headerName));
                if (String.isNotBlank(headerName) && headerValue != null && !isManagedHeaderName(headerName, config)) {
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
                if (String.isNotBlank(headerName) && headerValue != null && !isManagedHeaderName(headerName, config)) {
                    request.setHeader(headerName, headerValue);
                }
            }
        }
    }

    @TestVisible
    static List<String> takeBatch(List<String> sourceItems) {
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
    static List<String> dropBatch(List<String> sourceItems) {
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
        System.enqueueJob(new PublicApiStatusUpdateQueueable(remainingSerialized));
    }

    private static Map<Id, SObject> queryRecords(
        List<DeliveryItem> items,
        Map<Id, PublicApiConfigService.Config> configsById
    ) {
        Set<Id> recordIds = new Set<Id>();
        for (DeliveryItem item : items) {
            if (item != null && item.recordId != null) {
                recordIds.add(item.recordId);
            }
        }
        if (recordIds.isEmpty()) {
            return new Map<Id, SObject>();
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(SUBMISSION_OBJECT_API_NAME)) {
            return new Map<Id, SObject>();
        }
        Map<String, Schema.SObjectField> validFields =
            globalDescribe.get(SUBMISSION_OBJECT_API_NAME).getDescribe().fields.getMap();

        Set<String> selectedFields = new Set<String>{ 'Id' };
        for (PublicApiConfigService.Config config : configsById.values()) {
            Set<String> configuredFields = PublicApiRequestMappingService.getOutboundFieldApiNames(
                config == null ? null : config.requestFieldMappingsConfiguration,
                PublicApiRequestMappingService.getDefaultDirection()
            );
            for (String fieldName : configuredFields) {
                if (fieldName == 'CreatedDate' || validFields.containsKey(fieldName)) {
                    selectedFields.add(fieldName);
                }
            }
        }

        String soql = 'SELECT ' + String.join(new List<String>(selectedFields), ', ') +
            ' FROM ' + SUBMISSION_OBJECT_API_NAME + ' WHERE Id IN :recordIds';
        List<SObject> queried = Database.query(soql);
        return new Map<Id, SObject>(queried);
    }

    private static Map<Id, PublicApiConfigService.Config> resolveConfigsById(List<DeliveryItem> items) {
        Set<Id> configIds = new Set<Id>();
        for (DeliveryItem item : items) {
            if (item != null && item.configId != null) {
                configIds.add(item.configId);
            }
        }
        return PublicApiConfigService.getConfigsById(configIds);
    }

    @TestVisible
    static PublicApiWebhookDeliveryRecordService.DeliveryResult buildDeliveryResult(
        Boolean success,
        Integer statusCode,
        String responseBody,
        String message,
        String exceptionMessage
    ) {
        PublicApiWebhookDeliveryRecordService.DeliveryResult result =
            new PublicApiWebhookDeliveryRecordService.DeliveryResult();
        result.success = success;
        result.statusCode = statusCode;
        result.responseBody = responseBody;
        result.message = message;
        result.exceptionMessage = exceptionMessage;
        return result;
    }

    private static void applyLegacySignature(HttpRequest request, PublicApiConfigService.Config config, String payload) {
        if (String.isBlank(config.statusUpdateWebhookSecret)) {
            return;
        }
        String signature = PublicApiClient.generateWebhookSignature(payload, config.statusUpdateWebhookSecret);
        if (String.isNotBlank(signature)) {
            request.setHeader(DEFAULT_SIGNATURE_HEADER, signature);
        }
    }

    private static void applySignatureHeader(HttpRequest request, PublicApiConfigService.Config config, String payload) {
        String secret = normalizeConfigValue(config.statusUpdateWebhookSecret);
        if (String.isBlank(secret)) {
            return;
        }
        String signature = PublicApiClient.generateWebhookSignature(payload, secret);
        if (String.isBlank(signature)) {
            return;
        }
        request.setHeader(getConfiguredHeaderName(config, DEFAULT_SIGNATURE_HEADER), signature);
    }

    private static String getApiKeyHeaderName(PublicApiConfigService.Config config) {
        return getConfiguredHeaderName(config, DEFAULT_API_KEY_HEADER);
    }

    private static String getAuthorizationHeaderName(PublicApiConfigService.Config config) {
        return getConfiguredHeaderName(config, DEFAULT_AUTHORIZATION_HEADER);
    }

    private static String getConfiguredHeaderName(PublicApiConfigService.Config config, String fallback) {
        String configuredName = config == null ? null : normalizeConfigValue(config.outboundHeaderName);
        return String.isBlank(configuredName) ? fallback : configuredName;
    }

    private static String normalizeConfigValue(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String stringifyHeaderValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        if (String.isNotBlank(firstValue)) {
            return firstValue;
        }
        if (String.isNotBlank(secondValue)) {
            return secondValue;
        }
        return null;
    }

    private static Boolean isManagedHeaderName(String headerName, PublicApiConfigService.Config config) {
        if (String.isBlank(headerName)) {
            return false;
        }

        String normalizedHeader = headerName.trim().toLowerCase();
        if (normalizedHeader == 'content-type' || normalizedHeader == 'x-publicapi-event-type') {
            return true;
        }

        String authMode = normalizeConfigValue(config.outboundAuthMode);
        if (String.isBlank(authMode) && normalizedHeader == DEFAULT_SIGNATURE_HEADER.toLowerCase()) {
            return true;
        }
        if (authMode == AUTH_MODE_NONE || String.isBlank(authMode)) {
            return false;
        }

        String configuredName;
        if (authMode == AUTH_MODE_API_KEY_HEADER) {
            configuredName = getApiKeyHeaderName(config);
        } else if (authMode == AUTH_MODE_BEARER_TOKEN || authMode == AUTH_MODE_BASIC_AUTH) {
            configuredName = getAuthorizationHeaderName(config);
        } else if (authMode == AUTH_MODE_HMAC_SIGNATURE) {
            configuredName = getConfiguredHeaderName(config, DEFAULT_SIGNATURE_HEADER);
        } else {
            configuredName = null;
        }
        return String.isNotBlank(configuredName) && normalizedHeader == configuredName.toLowerCase();
    }
}
