/**
 * Resolves PublicApi configuration from the Public API Integration Config custom object.
 * Intake creation authenticates requests by matching the supplied API key to one active config record.
 */
public without sharing class PublicApiConfigService {

    public class Config {
        public Id id;
        public String webhookSecret;
        public String apiKey;
        public String statusUpdateWebhookUrl;
        public String statusUpdateWebhookSecret;
        public String outboundAuthMode;
        public String outboundHeaderName;
        public String outboundHeaderValue;
        public String outboundAdditionalHeadersJson;
        public String outboundContentType;
        public String requestFieldMappingsConfiguration;
    }

    public static Config getConfigForApiKey(String apiKey) {
        if (String.isBlank(apiKey)) {
            return null;
        }

        List<PublicApi_Integration_Config__c> settings =
            PublicApiConfigRepository.findActiveByApiKey(apiKey, 2);
        if (settings.isEmpty()) {
            return null;
        }
        if (settings.size() > 1) {
            throw new PublicApiIntakeServiceException(
                'PublicApi integration is misconfigured. Exactly one active Public API Integration Config record must match the supplied API key.'
            );
        }
        return fromSetting(settings[0]);
    }

    public static Config getConfigById(Id configId) {
        PublicApi_Integration_Config__c setting = PublicApiConfigRepository.findActiveById(configId);
        return setting == null ? null : fromSetting(setting);
    }

    public static Map<Id, Config> getConfigsById(Set<Id> configIds) {
        Map<Id, Config> configsById = new Map<Id, Config>();
        if (configIds == null || configIds.isEmpty()) {
            return configsById;
        }

        for (PublicApi_Integration_Config__c setting : PublicApiConfigRepository.findActiveByIds(configIds)) {
            configsById.put(setting.Id, fromSetting(setting));
        }
        return configsById;
    }

    private static Config fromSetting(PublicApi_Integration_Config__c setting) {
        Config c = new Config();
        c.id = setting.Id;
        c.webhookSecret = setting.Webhook_Secret__c;
        c.apiKey = setting.API_Key__c;
        c.statusUpdateWebhookUrl = setting.Outbound_Webhook_URL__c;
        c.statusUpdateWebhookSecret = setting.Outbound_Webhook_Secret__c;
        c.outboundAuthMode = setting.Outbound_Auth_Mode__c;
        c.outboundHeaderName = setting.Outbound_Header_Name__c;
        c.outboundHeaderValue = setting.Outbound_Header_Value__c;
        c.outboundAdditionalHeadersJson = setting.Outbound_Additional_Headers_JSON__c;
        c.outboundContentType = setting.Outbound_Content_Type__c;
        c.requestFieldMappingsConfiguration = setting.Outbound_Payload_Configuration__c;
        return c;
    }
}
