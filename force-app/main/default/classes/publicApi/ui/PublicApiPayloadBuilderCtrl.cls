public with sharing class PublicApiPayloadBuilderCtrl {
    public class PayloadSettings {
        @AuraEnabled public Boolean syncInboundAndOutbound;
        @AuraEnabled public String inboundConfigurationJson;
        @AuraEnabled public String outboundConfigurationJson;
        @AuraEnabled public String relatedRecordConfigurationJson;
        @AuraEnabled public Boolean outboundTriggerEnabled;
        @AuraEnabled public String outboundTriggerFieldName;
        @AuraEnabled public String outboundTriggerFieldValues;
        @AuraEnabled public String defaultInboundJson;
        @AuraEnabled public String defaultOutboundJson;
        @AuraEnabled public String targetObjectApiName;
        @AuraEnabled public List<String> availableObjectApiNames;
        @AuraEnabled public List<String> availableInboundFieldReferences;
        @AuraEnabled public List<String> availableOutboundFieldReferences;
        @AuraEnabled public List<String> availableLookupFieldNames;
        @AuraEnabled public List<String> availableTriggerFieldNames;
        @AuraEnabled public List<String> availableTriggerFieldValues;
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
        settings.inboundConfigurationJson = record.Inbound_Payload_Configuration__c;
        settings.outboundConfigurationJson = record.Outbound_Payload_Configuration__c;
        settings.relatedRecordConfigurationJson = record.Related_Record_Configuration__c;
        settings.syncInboundAndOutbound = record.Sync_Inbound_And_Outbound__c == null
            ? PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(
                settings.inboundConfigurationJson,
                settings.outboundConfigurationJson
            )
            : record.Sync_Inbound_And_Outbound__c;
        settings.outboundTriggerEnabled = record.Outbound_Trigger_Enabled__c == null
            ? true
            : record.Outbound_Trigger_Enabled__c;
        settings.outboundTriggerFieldName = normalizeBlank(record.Outbound_Trigger_Field_Name__c);
        settings.outboundTriggerFieldValues = normalizeLongTextBlank(record.Outbound_Trigger_Field_Values__c);
        settings.targetObjectApiName = normalizeBlank(record.Target_Object_API_Name__c);
        if (String.isBlank(settings.targetObjectApiName)) {
            settings.targetObjectApiName = PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME;
        }
        settings.defaultInboundJson = PublicApiPayloadTemplateService.getDefaultInboundMappingsJson();
        settings.defaultOutboundJson = PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson();
        settings.availableObjectApiNames = PublicApiPayloadTemplateService.getAvailableObjectApiNames();
        settings.availableInboundFieldReferences = PublicApiPayloadTemplateService.getAvailableFieldReferences(
            settings.targetObjectApiName,
            true
        );
        settings.availableOutboundFieldReferences = PublicApiPayloadTemplateService.getAvailableFieldReferences(
            settings.targetObjectApiName,
            false
        );
        settings.availableLookupFieldNames =
            PublicApiPayloadTemplateService.getAvailableLookupFieldNames(settings.targetObjectApiName);
        settings.availableTriggerFieldNames =
            PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(settings.targetObjectApiName);
        settings.availableTriggerFieldValues =
            PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(
                settings.targetObjectApiName,
                settings.outboundTriggerFieldName
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

    @AuraEnabled(cacheable=true)
    public static List<String> getLookupFieldNames(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<String>();
        }
        return PublicApiPayloadTemplateService.getAvailableLookupFieldNames(objectApiName.trim());
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getLookupTargetObjectApiNames(String objectApiName, String lookupFieldName) {
        if (String.isBlank(objectApiName) || String.isBlank(lookupFieldName)) {
            return new List<String>();
        }
        return PublicApiPayloadTemplateService.getAvailableLookupTargetObjectApiNames(
            objectApiName.trim(),
            lookupFieldName.trim()
        );
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getMatchFieldNames(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<String>();
        }
        return PublicApiPayloadTemplateService.getAvailableMatchFieldNames(objectApiName.trim());
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getCreateFieldNames(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<String>();
        }
        return PublicApiPayloadTemplateService.getAvailableCreateFieldNames(objectApiName.trim());
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTriggerFieldNames(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<String>();
        }
        return PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(objectApiName.trim());
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTriggerFieldValues(String objectApiName, String fieldName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldName)) {
            return new List<String>();
        }
        return PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(objectApiName.trim(), fieldName.trim());
    }

    @AuraEnabled
    public static void savePayloadSettings(
        Id recordId,
        Boolean syncInboundAndOutbound,
        String targetObjectApiName,
        String relatedRecordConfigurationJson,
        Boolean outboundTriggerEnabled,
        String outboundTriggerFieldName,
        String outboundTriggerFieldValues,
        String inboundConfigJson,
        String outboundConfigJson
    ) {
        if (recordId == null) {
            throwAuraException('Record ID is required.');
        }

        String normalizedTargetObjectApiName = normalizeObjectApiName(
            targetObjectApiName,
            'Target object API name is required.'
        );
        String normalizedTriggerFieldName = normalizeBlank(outboundTriggerFieldName);
        validateInboundMappingConfigurationJson(inboundConfigJson, normalizedTargetObjectApiName);
        validateOutboundMappingConfigurationJson(outboundConfigJson, normalizedTargetObjectApiName);
        validateRelatedRecordConfigurationJson(relatedRecordConfigurationJson, normalizedTargetObjectApiName);
        validateTriggerFieldConfiguration(
            normalizedTargetObjectApiName,
            normalizedTriggerFieldName,
            outboundTriggerFieldValues
        );

        update new PublicApi_Integration_Config__c(
            Id = recordId,
            Target_Object_API_Name__c = normalizedTargetObjectApiName,
            Sync_Inbound_And_Outbound__c = syncInboundAndOutbound,
            Outbound_Trigger_Enabled__c = outboundTriggerEnabled,
            Outbound_Trigger_Field_Name__c = normalizedTriggerFieldName,
            Outbound_Trigger_Field_Values__c = normalizeLongTextBlank(outboundTriggerFieldValues),
            Related_Record_Configuration__c =
                String.isNotBlank(relatedRecordConfigurationJson) ? relatedRecordConfigurationJson : null,
            Inbound_Payload_Configuration__c = String.isNotBlank(inboundConfigJson) ? inboundConfigJson : null,
            Outbound_Payload_Configuration__c = String.isNotBlank(outboundConfigJson) ? outboundConfigJson : null
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
            throwAuraException('Record ID is required.');
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
                throwAuraException(
                    allowArray
                        ? 'Configuration must be a JSON object or array.'
                        : 'Configuration must be a JSON object.'
                );
            }
        } catch (JSONException e) {
            throwAuraException('Invalid JSON: ' + e.getMessage());
        }
    }

    private static void validateInboundMappingConfigurationJson(
        String configJson,
        String targetObjectApiName
    ) {
        validateDirectionalMappingConfigurationJson(configJson, targetObjectApiName, true);
    }

    private static void validateOutboundMappingConfigurationJson(
        String configJson,
        String targetObjectApiName
    ) {
        validateDirectionalMappingConfigurationJson(configJson, targetObjectApiName, false);
    }

    private static void validateRelatedRecordConfigurationJson(
        String configJson,
        String targetObjectApiName
    ) {
        if (String.isBlank(configJson)) {
            return;
        }

        try {
            PublicApiRelatedRecordService.validateRules(configJson, targetObjectApiName);
        } catch (JSONException e) {
            throwAuraException('Invalid JSON: ' + e.getMessage());
        } catch (PublicApiIntakeServiceException e) {
            throwAuraException(e.getMessage());
        }
    }

    private static void validateDirectionalMappingConfigurationJson(
        String configJson,
        String targetObjectApiName,
        Boolean inboundMode
    ) {
        if (String.isBlank(configJson)) {
            return;
        }

        try {
            PublicApiRequestMappingService.parseMappings(configJson);
            if (inboundMode) {
                PublicApiRequestMappingService.validateInboundMappings(configJson, targetObjectApiName);
            } else {
                PublicApiRequestMappingService.validateOutboundMappings(configJson, targetObjectApiName);
            }
        } catch (JSONException e) {
            throwAuraException('Invalid JSON: ' + e.getMessage());
        } catch (PublicApiIntakeServiceException e) {
            throwAuraException(e.getMessage());
        }
    }

    private static String normalizeBlank(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String normalizeLongTextBlank(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String normalizeObjectApiName(String objectApiName, String requiredMessage) {
        String normalized = normalizeBlank(objectApiName);
        if (String.isBlank(normalized)) {
            throwAuraException(requiredMessage);
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(normalized)) {
            throwAuraException('Unknown object API name: ' + normalized);
        }
        return normalized;
    }

    private static void validateTriggerFieldConfiguration(
        String targetObjectApiName,
        String fieldName,
        String rawValues
    ) {
        if (String.isBlank(fieldName)) {
            return;
        }

        List<String> availableFieldNames =
            PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(targetObjectApiName);
        if (!availableFieldNames.contains(fieldName)) {
            throwAuraException('Select a valid outbound trigger field name for the target object.');
        }

        List<String> suggestedValues =
            PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(targetObjectApiName, fieldName);
        if (suggestedValues.isEmpty() || String.isBlank(rawValues)) {
            return;
        }

        Set<String> validValues = new Set<String>();
        for (String suggestedValue : suggestedValues) {
            validValues.add(suggestedValue);
        }

        for (String configuredValue : PublicApiOutboundTriggerService.parseTriggerFieldValues(rawValues)) {
            if (!validValues.contains(configuredValue)) {
                throwAuraException('Select valid outbound trigger values for ' + fieldName + '.');
            }
        }
    }

    private static void throwAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }
}
