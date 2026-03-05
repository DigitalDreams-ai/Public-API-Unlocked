public without sharing class PublicApiStatusUpdateDeliveryService {
    @TestVisible static final String DEFAULT_CONTENT_TYPE = 'application/json';
    @TestVisible static final String DEFAULT_API_KEY_HEADER = 'X-API-KEY';
    @TestVisible static final String DEFAULT_AUTHORIZATION_HEADER = 'Authorization';
    @TestVisible static final String DEFAULT_SIGNATURE_HEADER = 'x-publicapi-signature';
    @TestVisible static Set<String> provisionedWebhookDomainsInTransaction = new Set<String>();

    @TestVisible static final String AUTH_MODE_NONE = 'None';
    @TestVisible static final String AUTH_MODE_API_KEY_HEADER = 'ApiKeyHeader';
    @TestVisible static final String AUTH_MODE_BEARER_TOKEN = 'BearerToken';
    @TestVisible static final String AUTH_MODE_BASIC_AUTH = 'BasicAuth';
    @TestVisible static final String AUTH_MODE_HMAC_SIGNATURE = 'HmacSignature';

    public class SendOutcome {
        public String payloadJson;
        public PublicApiWebhookDeliveryRecordService.DeliveryResult deliveryResult;
    }

    public static SendOutcome sendStatusUpdate(
        Http http,
        SObject record,
        PublicApiConfigService.Config config
    ) {
        return sendStatusUpdate(http, record, config, null);
    }

    public static SendOutcome sendStatusUpdate(
        Http http,
        SObject record,
        PublicApiConfigService.Config config,
        String sessionId
    ) {
        SendOutcome outcome = new SendOutcome();
        if (http == null || record == null || config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
            return outcome;
        }

        try {
            validateOutboundMappings(config.requestFieldMappingsConfiguration);
            Map<String, Object> payloadMap = PublicApiRequestMappingService.buildOutboundPayload(
                record,
                config.requestFieldMappingsConfiguration,
                PublicApiRequestMappingService.getDefaultDirection()
            );
            if (payloadMap == null || payloadMap.isEmpty()) {
                throw new PublicApiIntakeServiceException(
                    'Outbound mapping produced an empty payload. Ensure outbound mappings are configured and valid.'
                );
            }
            outcome.payloadJson = JSON.serialize(payloadMap);
            ensureWebhookDomainIsProvisioned(config.statusUpdateWebhookUrl, sessionId);

            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setEndpoint(config.statusUpdateWebhookUrl);
            request.setBody(outcome.payloadJson);
            applyRequestConfiguration(request, config, outcome.payloadJson);

            HttpResponse response = http.send(request);
            outcome.deliveryResult = buildDeliveryResult(
                response.getStatusCode() >= 200 && response.getStatusCode() < 300,
                response.getStatusCode(),
                response.getBody(),
                response.getStatus(),
                null
            );
        } catch (Exception e) {
            outcome.deliveryResult = buildDeliveryResult(false, null, null, null, e.getMessage());
        }
        return outcome;
    }

    @TestVisible
    static void ensureWebhookDomainIsProvisioned(String webhookUrl, String sessionId) {
        if (String.isBlank(webhookUrl)) {
            return;
        }
        String normalizedSessionId = String.isBlank(sessionId) ? null : sessionId.trim();
        if (String.isBlank(normalizedSessionId)) {
            return;
        }
        String domainUrl = PublicApiRemoteSiteSettingService.extractDomainFromUrl(webhookUrl);
        if (String.isBlank(domainUrl) || provisionedWebhookDomainsInTransaction.contains(domainUrl)) {
            return;
        }
        PublicApiRemoteSiteSettingService.ensureStatusWebhookRemoteSite(domainUrl, normalizedSessionId);
        provisionedWebhookDomainsInTransaction.add(domainUrl);
    }

    @TestVisible
    static void validateOutboundMappings(String mappingConfigurationJson) {
        if (String.isBlank(mappingConfigurationJson)) {
            throw new PublicApiIntakeServiceException(
                'Outbound mapping configuration is required on Public API Integration Config.'
            );
        }
        PublicApiRequestMappingService.validateMappings(mappingConfigurationJson, 'Outbound');
    }

    public static Map<Id, SObject> queryRecords(
        List<PublicApiStatusUpdateQueueable.DeliveryItem> items,
        Map<Id, PublicApiConfigService.Config> configsById,
        String submissionObjectApiName
    ) {
        Set<Id> recordIds = new Set<Id>();
        for (PublicApiStatusUpdateQueueable.DeliveryItem item : items) {
            if (item != null && item.recordId != null) {
                recordIds.add(item.recordId);
            }
        }
        if (recordIds.isEmpty()) {
            return new Map<Id, SObject>();
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(submissionObjectApiName)) {
            return new Map<Id, SObject>();
        }
        Map<String, Schema.SObjectField> validFields =
            globalDescribe.get(submissionObjectApiName).getDescribe().fields.getMap();

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
            ' FROM ' + submissionObjectApiName + ' WHERE Id IN :recordIds';
        List<SObject> queried = Database.query(soql);
        return new Map<Id, SObject>(queried);
    }

    public static void applyRequestConfiguration(HttpRequest request, PublicApiConfigService.Config config, String payload) {
        request.setHeader('Content-Type', getContentType(config));
        request.setHeader('X-PublicApi-Event-Type', 'status_changed');
        applyAuthHeaders(request, config, payload);
        applyAdditionalHeaders(request, config);
    }

    public static String getContentType(PublicApiConfigService.Config config) {
        String configured = config == null ? null : normalizeConfigValue(config.outboundContentType);
        return String.isBlank(configured) ? DEFAULT_CONTENT_TYPE : configured;
    }

    public static void applyAuthHeaders(HttpRequest request, PublicApiConfigService.Config config, String payload) {
        if (request == null || config == null) {
            return;
        }

        String authMode = normalizeConfigValue(config.outboundAuthMode);
        if (String.isBlank(authMode) || authMode == AUTH_MODE_NONE) {
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

    public static void applyAdditionalHeaders(HttpRequest request, PublicApiConfigService.Config config) {
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

    private static PublicApiWebhookDeliveryRecordService.DeliveryResult buildDeliveryResult(
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
