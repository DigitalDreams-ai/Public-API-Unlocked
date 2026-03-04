public with sharing class UnbounceJsonPayloadBuilderController {
    public class HeaderSettings {
        @AuraEnabled public String authMode;
        @AuraEnabled public String contentType;
        @AuraEnabled public String headerName;
        @AuraEnabled public String headerValue;
        @AuraEnabled public String additionalHeadersJson;
        @AuraEnabled public Boolean hasWebhookSecret;
    }

    @AuraEnabled(cacheable=true)
    public static String getDefaultPayloadSchema() {
        return JSON.serializePretty(UnbouncePayloadTemplateService.getDefaultTemplateSchema());
    }

    @AuraEnabled(cacheable=true)
    public static String getConfiguration(Id recordId) {
        if (recordId == null) {
            return null;
        }

        List<Unbounce_Integration_Config__c> records = [
            SELECT Outbound_Payload_Configuration__c
            FROM Unbounce_Integration_Config__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0].Outbound_Payload_Configuration__c;
    }

    @AuraEnabled(cacheable=true)
    public static HeaderSettings getHeaderSettings(Id recordId) {
        if (recordId == null) {
            return null;
        }

        List<Unbounce_Integration_Config__c> records = [
            SELECT Outbound_Auth_Mode__c,
                   Outbound_Content_Type__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Webhook_Secret__c
            FROM Unbounce_Integration_Config__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (records.isEmpty()) {
            return null;
        }

        Unbounce_Integration_Config__c record = records[0];
        HeaderSettings settings = new HeaderSettings();
        settings.authMode = record.Outbound_Auth_Mode__c;
        settings.contentType = record.Outbound_Content_Type__c;
        settings.headerName = record.Outbound_Header_Name__c;
        settings.headerValue = record.Outbound_Header_Value__c;
        settings.additionalHeadersJson = record.Outbound_Additional_Headers_JSON__c;
        settings.hasWebhookSecret = String.isNotBlank(record.Outbound_Webhook_Secret__c);
        return settings;
    }

    @AuraEnabled
    public static void saveConfiguration(Id recordId, String configJson) {
        if (recordId == null) {
            AuraHandledException ex = new AuraHandledException('Record ID is required.');
            ex.setMessage('Record ID is required.');
            throw ex;
        }

        validateConfigurationJson(configJson, false);

        update new Unbounce_Integration_Config__c(
            Id = recordId,
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

        update new Unbounce_Integration_Config__c(
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
            if (!(parsed instanceof Map<String, Object>) && !(allowArray && parsed instanceof List<Object>)) {
                AuraHandledException ex = new AuraHandledException(
                    allowArray
                        ? 'Configuration must be a JSON object or array.'
                        : 'Configuration must be a JSON object, not an array or primitive.'
                );
                ex.setMessage(
                    allowArray
                        ? 'Configuration must be a JSON object or array.'
                        : 'Configuration must be a JSON object, not an array or primitive.'
                );
                throw ex;
            }
        } catch (JSONException e) {
            String message = 'Invalid JSON: ' + e.getMessage();
            AuraHandledException ex = new AuraHandledException(message);
            ex.setMessage(message);
            throw ex;
        }
    }

    private static String normalizeBlank(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
