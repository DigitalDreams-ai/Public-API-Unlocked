public with sharing class PublicApiPayloadBuilderCtrl {
    public class PayloadSettings {
        @AuraEnabled public Boolean syncInboundAndOutbound;
        @AuraEnabled public String configurationJson;
        @AuraEnabled public String defaultJson;
        @AuraEnabled public String inboundTargetObjectApiName;
        @AuraEnabled public String outboundSourceObjectApiName;
        @AuraEnabled public List<String> availableObjectApiNames;
        @AuraEnabled public List<String> availableInboundFieldReferences;
        @AuraEnabled public List<String> availableOutboundFieldReferences;
    }

    public class HeaderSettings {
        @AuraEnabled public String authMode;
        @AuraEnabled public String contentType;
        @AuraEnabled public String headerName;
        @AuraEnabled public String headerValue;
        @AuraEnabled public String additionalHeadersJson;
        @AuraEnabled public Boolean hasWebhookSecret;
    }

    @AuraEnabled(cacheable=true)
    public static PayloadSettings getPayloadSettings(Id recordId) {
        if (recordId == null) {
            return null;
        }

        PublicApi_Integration_Config__c record = PublicApiConfigRepository.findById(recordId);
        if (record == null) {
            return null;
        }

        PayloadSettings settings = new PayloadSettings();
        settings.configurationJson = record.Outbound_Payload_Configuration__c;
        settings.syncInboundAndOutbound = PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(
            settings.configurationJson
        );
        settings.inboundTargetObjectApiName = String.isBlank(record.Inbound_Target_Object_API_Name__c)
            ? PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
            : record.Inbound_Target_Object_API_Name__c.trim();
        settings.outboundSourceObjectApiName = String.isBlank(record.Outbound_Source_Object_API_Name__c)
            ? PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
            : record.Outbound_Source_Object_API_Name__c.trim();
        settings.defaultJson = PublicApiPayloadTemplateService.getDefaultMappingsJson();
        settings.availableObjectApiNames = PublicApiPayloadTemplateService.getAvailableObjectApiNames();
        settings.availableInboundFieldReferences = PublicApiPayloadTemplateService.getAvailableFieldReferences(
            settings.inboundTargetObjectApiName,
            true
        );
        settings.availableOutboundFieldReferences = PublicApiPayloadTemplateService.getAvailableFieldReferences(
            settings.outboundSourceObjectApiName,
            false
        );
        return settings;
    }

    @AuraEnabled(cacheable=true)
    public static HeaderSettings getHeaderSettings(Id recordId) {
        if (recordId == null) {
            return null;
        }

        PublicApi_Integration_Config__c record = PublicApiConfigRepository.findById(recordId);
        if (record == null) {
            return null;
        }

        HeaderSettings settings = new HeaderSettings();
        settings.authMode = record.Outbound_Auth_Mode__c;
        settings.contentType = record.Outbound_Content_Type__c;
        settings.headerName = record.Outbound_Header_Name__c;
        settings.headerValue = record.Outbound_Header_Value__c;
        settings.additionalHeadersJson = record.Outbound_Additional_Headers_JSON__c;
        settings.hasWebhookSecret = String.isNotBlank(record.Outbound_Webhook_Secret__c);
        return settings;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getFieldReferences(String objectApiName, Boolean inboundMode) {
        if (String.isBlank(objectApiName)) {
            return new List<String>();
        }
        return PublicApiPayloadTemplateService.getAvailableFieldReferences(objectApiName.trim(), inboundMode);
    }

    @AuraEnabled
    public static void savePayloadSettings(
        Id recordId,
        Boolean syncInboundAndOutbound,
        String inboundTargetObjectApiName,
        String outboundSourceObjectApiName,
        String configJson
    ) {
        if (recordId == null) {
            AuraHandledException ex = new AuraHandledException('Record ID is required.');
            ex.setMessage('Record ID is required.');
            throw ex;
        }

        String normalizedInboundObjectApiName = normalizeObjectApiName(
            inboundTargetObjectApiName,
            'Inbound target object API name is required.'
        );
        String normalizedOutboundObjectApiName = normalizeObjectApiName(
            outboundSourceObjectApiName,
            'Outbound source object API name is required.'
        );
        validateMappingConfigurationJson(
            configJson,
            normalizedInboundObjectApiName,
            normalizedOutboundObjectApiName
        );

        update new PublicApi_Integration_Config__c(
            Id = recordId,
            Inbound_Target_Object_API_Name__c = normalizedInboundObjectApiName,
            Outbound_Source_Object_API_Name__c = normalizedOutboundObjectApiName,
            Outbound_Payload_Configuration__c = String.isNotBlank(configJson) ? configJson : null
        );
    }

    @AuraEnabled
    public static void saveHeaderSettings(
        Id recordId,
        String authMode,
        String contentType,
        String headerName,
        String headerValue,
        String additionalHeadersJson
    ) {
        if (recordId == null) {
            AuraHandledException ex = new AuraHandledException('Record ID is required.');
            ex.setMessage('Record ID is required.');
            throw ex;
        }

        validateConfigurationJson(additionalHeadersJson, true);

        update new PublicApi_Integration_Config__c(
            Id = recordId,
            Outbound_Auth_Mode__c = normalizeBlank(authMode),
            Outbound_Content_Type__c = normalizeBlank(contentType),
            Outbound_Header_Name__c = normalizeBlank(headerName),
            Outbound_Header_Value__c = normalizeBlank(headerValue),
            Outbound_Additional_Headers_JSON__c = String.isNotBlank(additionalHeadersJson) ? additionalHeadersJson : null
        );
    }

    private static void validateConfigurationJson(String configJson, Boolean allowArray) {
        if (String.isBlank(configJson)) {
            return;
        }

        try {
            Object parsed = JSON.deserializeUntyped(configJson);
            Boolean isValid =
                parsed instanceof Map<String, Object> ||
                (allowArray && parsed instanceof List<Object>);
            if (!isValid) {
                String message = allowArray
                    ? 'Configuration must be a JSON object or array.'
                    : 'Configuration must be a JSON object.';
                AuraHandledException ex = new AuraHandledException(message);
                ex.setMessage(message);
                throw ex;
            }
        } catch (JSONException e) {
            String message = 'Invalid JSON: ' + e.getMessage();
            AuraHandledException ex = new AuraHandledException(message);
            ex.setMessage(message);
            throw ex;
        }
    }

    private static void validateMappingConfigurationJson(
        String configJson,
        String inboundTargetObjectApiName,
        String outboundSourceObjectApiName
    ) {
        if (String.isBlank(configJson)) {
            return;
        }

        try {
            PublicApiRequestMappingService.MappingConfiguration mappings =
                PublicApiRequestMappingService.parseConfiguration(configJson);
            if (mappings.inboundMappings.isEmpty() && mappings.outboundMappings.isEmpty()) {
                AuraHandledException ex = new AuraHandledException(
                    'Mappings configuration must contain at least one valid row.'
                );
                ex.setMessage('Mappings configuration must contain at least one valid row.');
                throw ex;
            }
            PublicApiRequestMappingService.validateMappings(
                configJson,
                PublicApiRequestMappingService.getDefaultDirection(),
                inboundTargetObjectApiName,
                outboundSourceObjectApiName
            );
        } catch (JSONException e) {
            String message = 'Invalid JSON: ' + e.getMessage();
            AuraHandledException ex = new AuraHandledException(message);
            ex.setMessage(message);
            throw ex;
        } catch (PublicApiIntakeServiceException e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static String normalizeBlank(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String normalizeObjectApiName(String objectApiName, String requiredMessage) {
        String normalized = normalizeBlank(objectApiName);
        if (String.isBlank(normalized)) {
            AuraHandledException ex = new AuraHandledException(requiredMessage);
            ex.setMessage(requiredMessage);
            throw ex;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(normalized)) {
            AuraHandledException ex = new AuraHandledException('Unknown object API name: ' + normalized);
            ex.setMessage('Unknown object API name: ' + normalized);
            throw ex;
        }
        return normalized;
    }

}
