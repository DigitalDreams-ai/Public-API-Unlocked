public without sharing class PublicApiStatusUpdateDeliveryService {
    @TestVisible static final String DEFAULT_CONTENT_TYPE = 'application/json';
    @TestVisible static final String DEFAULT_API_KEY_HEADER = 'X-API-KEY';
    @TestVisible static final String DEFAULT_AUTHORIZATION_HEADER = 'Authorization';
    @TestVisible static final String DEFAULT_SIGNATURE_HEADER = 'x-publicapi-signature';

    @TestVisible static final String AUTH_MODE_NONE = 'None';
    @TestVisible static final String AUTH_MODE_API_KEY_HEADER = 'ApiKeyHeader';
    @TestVisible static final String AUTH_MODE_BEARER_TOKEN = 'BearerToken';
    @TestVisible static final String AUTH_MODE_BASIC_AUTH = 'BasicAuth';
    @TestVisible static final String AUTH_MODE_HMAC_SIGNATURE = 'HmacSignature';
    @TestVisible public static final String ERROR_CODE_MAPPING_ERROR = 'MAPPING_ERROR';
    @TestVisible public static final String ERROR_CODE_AUTH_HEADER_ERROR = 'AUTH_HEADER_ERROR';
    @TestVisible public static final String ERROR_CODE_REMOTE_SITE_ERROR = 'REMOTE_SITE_ERROR';
    @TestVisible public static final String ERROR_CODE_WEBHOOK_RESPONSE_ERROR = 'WEBHOOK_RESPONSE_ERROR';
    @TestVisible public static final String ERROR_CODE_WEBHOOK_CALLOUT_ERROR = 'WEBHOOK_CALLOUT_ERROR';
    @TestVisible public static final String ERROR_CODE_UNKNOWN_ERROR = 'UNKNOWN_ERROR';

    public class SendOutcome {
        public String payloadJson;
        public PublicApiWebhookDeliveryRecordService.DeliveryResult deliveryResult;
    }

    public static SendOutcome sendStatusUpdate(
        Http http,
        SObject record,
        PublicApiConfigService.Config config
    ) {
        SendOutcome outcome = new SendOutcome();
        if (http == null || record == null || config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
            return outcome;
        }

        try {
            validateOutboundMappings(config.outboundPayloadConfiguration, config.targetObjectApiName);
            Map<String, Object> payloadMap = PublicApiRequestMappingService.buildOutboundPayload(
                record,
                config.outboundPayloadConfiguration,
                config.targetObjectApiName
            );
            if (payloadMap == null || payloadMap.isEmpty()) {
                throw new PublicApiIntakeServiceException(
                    'Outbound mapping produced an empty payload. Ensure outbound mappings are configured and valid.'
                );
            }
            outcome.payloadJson = JSON.serialize(payloadMap);
            validateProvisionedWebhookDomain(config);

            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setEndpoint(config.statusUpdateWebhookUrl);
            request.setBody(outcome.payloadJson);
            applyRequestConfiguration(request, config, outcome.payloadJson);

            HttpResponse response = http.send(request);
            Boolean isSuccess = response.getStatusCode() >= 200 && response.getStatusCode() < 300;
            outcome.deliveryResult = buildDeliveryResult(
                isSuccess,
                response.getStatusCode(),
                isSuccess ? null : resolveHttpErrorCode(response.getStatusCode()),
                response.getBody(),
                response.getStatus(),
                null
            );
        } catch (Exception e) {
            outcome.deliveryResult = buildDeliveryResult(
                false,
                null,
                resolveExceptionErrorCode(e),
                null,
                null,
                e.getMessage()
            );
        }
        return outcome;
    }

    @TestVisible
    static void validateProvisionedWebhookDomain(PublicApiConfigService.Config config) {
        if (config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
            return;
        }

        String expectedDomain = PublicApiRemoteSiteSettingService.extractDomainFromUrl(config.statusUpdateWebhookUrl);
        if (String.isBlank(expectedDomain)) {
            throw new PublicApiRemoteSiteSettingException(
                'Webhook domain is invalid. Save the Public API Integration Config with a valid outbound webhook URL.'
            );
        }

        if (config.outboundRemoteSiteStatus != PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED) {
            throw new PublicApiRemoteSiteSettingException(
                'Webhook domain is not provisioned for this configuration. Save the Public API Integration Config as an API-enabled user to provision the remote site before outbound delivery.'
            );
        }

        if (String.isBlank(config.outboundRemoteSiteDomain) ||
            config.outboundRemoteSiteDomain.trim().toLowerCase() != expectedDomain.trim().toLowerCase()) {
            throw new PublicApiRemoteSiteSettingException(
                'Webhook domain provisioning is out of date for this configuration. Save the Public API Integration Config to reprovision the current webhook domain before outbound delivery.'
            );
        }
    }

    @TestVisible
    static void validateOutboundMappings(
        String outboundConfigurationJson,
        String targetObjectApiName
    ) {
        if (String.isBlank(outboundConfigurationJson)) {
            throw new PublicApiIntakeServiceException(
                'Outbound mapping configuration is required on Public API Integration Config.'
            );
        }
        PublicApiRequestMappingService.validateOutboundMappings(outboundConfigurationJson, targetObjectApiName);
    }

    @TestVisible
    static void validateOutboundMappings(String outboundConfigurationJson) {
        validateOutboundMappings(outboundConfigurationJson, PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME);
    }

    public static Map<Id, SObject> queryRecords(
        List<PublicApiStatusUpdateQueueable.DeliveryItem> items,
        Map<Id, PublicApiConfigService.Config> configsById
    ) {
        Map<String, Set<Id>> recordIdsByObject = new Map<String, Set<Id>>();
        Map<String, Set<Id>> configIdsByObject = new Map<String, Set<Id>>();
        for (PublicApiStatusUpdateQueueable.DeliveryItem item : items) {
            if (item == null || item.recordId == null || item.configId == null) {
                continue;
            }
            PublicApiConfigService.Config config = configsById.get(item.configId);
            if (config == null || String.isBlank(config.targetObjectApiName)) {
                continue;
            }
            String objectApiName = config.targetObjectApiName.trim();
            if (!recordIdsByObject.containsKey(objectApiName)) {
                recordIdsByObject.put(objectApiName, new Set<Id>());
            }
            recordIdsByObject.get(objectApiName).add(item.recordId);

            if (!configIdsByObject.containsKey(objectApiName)) {
                configIdsByObject.put(objectApiName, new Set<Id>());
            }
            configIdsByObject.get(objectApiName).add(item.configId);
        }
        if (recordIdsByObject.isEmpty()) {
            return new Map<Id, SObject>();
        }

        Map<Id, SObject> recordsById = new Map<Id, SObject>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String objectApiName : recordIdsByObject.keySet()) {
            if (String.isBlank(objectApiName) || !globalDescribe.containsKey(objectApiName)) {
                continue;
            }
            Set<Id> recordIdsForObject = recordIdsByObject.get(objectApiName);
            if (recordIdsForObject == null || recordIdsForObject.isEmpty()) {
                continue;
            }

            Map<String, Schema.SObjectField> validFields = globalDescribe.get(objectApiName).getDescribe().fields.getMap();
            Set<String> selectedFields = new Set<String>{ 'Id' };
            for (Id configId : configIdsByObject.get(objectApiName)) {
                PublicApiConfigService.Config config = configsById.get(configId);
                Set<String> configuredFields = PublicApiRequestMappingService.getOutboundFieldApiNames(
                    config == null ? null : config.outboundPayloadConfiguration,
                    objectApiName
                );
                for (String fieldName : configuredFields) {
                    if (fieldName == 'CreatedDate' || validFields.containsKey(fieldName)) {
                        selectedFields.add(fieldName);
                    }
                }
            }

            String soql = 'SELECT ' + String.join(new List<String>(selectedFields), ', ') +
                ' FROM ' + objectApiName + ' WHERE Id IN :recordIdsForObject';
            for (SObject queriedRecord : Database.query(soql)) {
                recordsById.put((Id) queriedRecord.get('Id'), queriedRecord);
            }
        }
        return recordsById;
    }

    @TestVisible
    static Map<Id, SObject> queryRecords(
        List<PublicApiStatusUpdateQueueable.DeliveryItem> items,
        Map<Id, PublicApiConfigService.Config> configsById,
        String submissionObjectApiName
    ) {
        return queryRecords(items, configsById);
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
        validateAuthConfiguration(config, authMode);
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

        try {
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
        } catch (JSONException e) {
            throw new PublicApiIntakeServiceException(
                'Outbound header configuration is invalid: ' + e.getMessage()
            );
        }
    }

    private static PublicApiWebhookDeliveryRecordService.DeliveryResult buildDeliveryResult(
        Boolean success,
        Integer statusCode,
        String errorCode,
        String responseBody,
        String message,
        String exceptionMessage
    ) {
        PublicApiWebhookDeliveryRecordService.DeliveryResult result =
            new PublicApiWebhookDeliveryRecordService.DeliveryResult();
        result.success = success;
        result.statusCode = statusCode;
        result.errorCode = errorCode;
        result.responseBody = responseBody;
        result.message = message;
        result.exceptionMessage = exceptionMessage;
        return result;
    }

    private static void validateAuthConfiguration(PublicApiConfigService.Config config, String authMode) {
        if (config == null || String.isBlank(authMode)) {
            return;
        }

        String headerValue = normalizeConfigValue(config.outboundHeaderValue);
        if ((authMode == AUTH_MODE_API_KEY_HEADER ||
            authMode == AUTH_MODE_BEARER_TOKEN ||
            authMode == AUTH_MODE_BASIC_AUTH) &&
            String.isBlank(headerValue)) {
            throw new PublicApiIntakeServiceException(
                'Outbound auth configuration is invalid: Outbound Header Value is required for auth mode ' + authMode + '.'
            );
        }

        String webhookSecret = normalizeConfigValue(config.statusUpdateWebhookSecret);
        if (authMode == AUTH_MODE_HMAC_SIGNATURE && String.isBlank(webhookSecret)) {
            throw new PublicApiIntakeServiceException(
                'Outbound auth configuration is invalid: Outbound Webhook Secret is required for HMAC signature mode.'
            );
        }
    }

    @TestVisible
    static String resolveHttpErrorCode(Integer statusCode) {
        if (statusCode == null) {
            return ERROR_CODE_WEBHOOK_RESPONSE_ERROR;
        }
        if (statusCode == 401 || statusCode == 403) {
            return ERROR_CODE_AUTH_HEADER_ERROR;
        }
        return ERROR_CODE_WEBHOOK_RESPONSE_ERROR;
    }

    @TestVisible
    static String resolveExceptionErrorCode(Exception ex) {
        if (ex == null) {
            return ERROR_CODE_UNKNOWN_ERROR;
        }
        if (ex instanceof PublicApiRemoteSiteSettingException) {
            return ERROR_CODE_REMOTE_SITE_ERROR;
        }
        if (ex instanceof JSONException) {
            return ERROR_CODE_MAPPING_ERROR;
        }
        if (ex instanceof CalloutException) {
            return ERROR_CODE_WEBHOOK_CALLOUT_ERROR;
        }

        String message = String.valueOf(ex.getMessage()).toLowerCase();
        if (message.contains('mapping') || message.contains('field reference') || message.contains('outbound payload')) {
            return ERROR_CODE_MAPPING_ERROR;
        }
        if (message.contains('auth configuration') || message.contains('header configuration') || message.contains('authorization')) {
            return ERROR_CODE_AUTH_HEADER_ERROR;
        }
        if (message.contains('remote site') || message.contains('metadata api')) {
            return ERROR_CODE_REMOTE_SITE_ERROR;
        }
        return ERROR_CODE_UNKNOWN_ERROR;
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
