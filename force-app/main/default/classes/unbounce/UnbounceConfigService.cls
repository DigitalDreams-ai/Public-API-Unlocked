/**
 * Resolves Unbounce configuration from the Unbounce Integration Config custom object.
 * Intake creation authenticates requests by matching the supplied API key to one active config record.
 */
public without sharing class UnbounceConfigService {

    public class Config {
        public Id id;
        public String webhookSecret;
        public String apiKey;
        public String referredByPartyName;
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

        List<Unbounce_Integration_Config__c> settings = [
            SELECT Id,
                   Webhook_Secret__c,
                   API_Key__c,
                   Referred_By_Party_Name__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Request_Field_Mappings__c
            FROM Unbounce_Integration_Config__c
            WHERE Is_Active__c = true
            AND API_Key__c = :apiKey.trim()
            ORDER BY CreatedDate DESC
            LIMIT 2
        ];
        if (settings.isEmpty()) {
            return null;
        }
        if (settings.size() > 1) {
            throw new UnbounceIntakeServiceException(
                'Unbounce integration is misconfigured. Exactly one active Unbounce Integration Config record must match the supplied API key.'
            );
        }
        return fromSetting(settings[0]);
    }

    public static Config getConfigById(Id configId) {
        if (configId == null) {
            return null;
        }

        List<Unbounce_Integration_Config__c> settings = [
            SELECT Id,
                   Webhook_Secret__c,
                   API_Key__c,
                   Referred_By_Party_Name__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Request_Field_Mappings__c
            FROM Unbounce_Integration_Config__c
            WHERE Id = :configId
            AND Is_Active__c = true
            LIMIT 1
        ];
        return settings.isEmpty() ? null : fromSetting(settings[0]);
    }

    public static Map<Id, Config> getConfigsById(Set<Id> configIds) {
        Map<Id, Config> configsById = new Map<Id, Config>();
        if (configIds == null || configIds.isEmpty()) {
            return configsById;
        }

        for (Unbounce_Integration_Config__c setting : [
            SELECT Id,
                   Webhook_Secret__c,
                   API_Key__c,
                   Referred_By_Party_Name__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Request_Field_Mappings__c
            FROM Unbounce_Integration_Config__c
            WHERE Id IN :configIds
            AND Is_Active__c = true
        ]) {
            configsById.put(setting.Id, fromSetting(setting));
        }
        return configsById;
    }

    private static Config fromSetting(Unbounce_Integration_Config__c setting) {
        Config c = new Config();
        c.id = setting.Id;
        c.webhookSecret = setting.Webhook_Secret__c;
        c.apiKey = setting.API_Key__c;
        c.referredByPartyName = setting.Referred_By_Party_Name__c;
        c.statusUpdateWebhookUrl = setting.Outbound_Webhook_URL__c;
        c.statusUpdateWebhookSecret = setting.Outbound_Webhook_Secret__c;
        c.outboundAuthMode = setting.Outbound_Auth_Mode__c;
        c.outboundHeaderName = setting.Outbound_Header_Name__c;
        c.outboundHeaderValue = setting.Outbound_Header_Value__c;
        c.outboundAdditionalHeadersJson = setting.Outbound_Additional_Headers_JSON__c;
        c.outboundContentType = setting.Outbound_Content_Type__c;
        c.requestFieldMappingsConfiguration = setting.Request_Field_Mappings__c;
        return c;
    }
}
