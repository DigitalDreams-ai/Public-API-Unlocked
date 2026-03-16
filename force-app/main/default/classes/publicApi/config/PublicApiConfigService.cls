/**
 * Resolves PublicApi configuration from the Public API Integration Config custom object.
 * Submission processing authenticates requests by matching the supplied API key to one active config record.
 */
public without sharing class PublicApiConfigService {
    @TestVisible
    public static final String DEFAULT_SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';
    @TestVisible
    public static final String REMOTE_SITE_STATUS_PENDING = 'Pending';
    @TestVisible
    public static final String REMOTE_SITE_STATUS_PROVISIONED = 'Provisioned';
    @TestVisible
    public static final String REMOTE_SITE_STATUS_FAILED = 'Failed';

    public class Config {
        public Id id;
        public String webhookSecret;
        public String apiKey;
        public Boolean outboundTriggerEnabled;
        public String outboundTriggerFieldName;
        public String outboundTriggerFieldValues;
        public String statusUpdateWebhookUrl;
        public String statusUpdateWebhookSecret;
        public String outboundAuthMode;
        public String outboundHeaderName;
        public String outboundHeaderValue;
        public String outboundAdditionalHeadersJson;
        public String outboundContentType;
        public String inboundPayloadConfiguration;
        public String outboundPayloadConfiguration;
        public String relatedRecordConfiguration;
        public String targetObjectApiName;
        public String targetRecordTypeDeveloperName;
        public Boolean syncInboundAndOutbound;
        public String outboundRemoteSiteDomain;
        public String outboundRemoteSiteName;
        public String outboundRemoteSiteStatus;
        public String outboundRemoteSiteLastError;
        public Datetime outboundRemoteSiteLastProvisionedAt;
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
            throw new PublicApiSubmissionServiceException(
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

    public static List<Config> getConfigsForTargetObject(String targetObjectApiName) {
        List<Config> configs = new List<Config>();
        if (String.isBlank(targetObjectApiName)) {
            return configs;
        }

        for (PublicApi_Integration_Config__c setting :
            PublicApiConfigRepository.findActiveByTargetObjectApiName(targetObjectApiName)) {
            configs.add(fromSetting(setting));
        }
        return configs;
    }

    private static Config fromSetting(PublicApi_Integration_Config__c setting) {
        Config c = new Config();
        c.id = setting.Id;
        c.webhookSecret = setting.Webhook_Secret__c;
        c.apiKey = setting.API_Key__c;
        c.outboundTriggerEnabled = setting.Outbound_Trigger_Enabled__c;
        c.outboundTriggerFieldName = setting.Outbound_Trigger_Field_Name__c;
        c.outboundTriggerFieldValues = setting.Outbound_Trigger_Field_Values__c;
        c.statusUpdateWebhookUrl = setting.Outbound_Webhook_URL__c;
        c.outboundRemoteSiteDomain = setting.Outbound_Remote_Site_Domain__c;
        c.outboundRemoteSiteName = setting.Outbound_Remote_Site_Name__c;
        c.outboundRemoteSiteStatus = setting.Outbound_Remote_Site_Status__c;
        c.outboundRemoteSiteLastError = setting.Outbound_Remote_Site_Last_Error__c;
        c.outboundRemoteSiteLastProvisionedAt = setting.Outbound_Remote_Site_Last_Provisioned_At__c;
        c.statusUpdateWebhookSecret = setting.Outbound_Webhook_Secret__c;
        c.outboundAuthMode = setting.Outbound_Auth_Mode__c;
        c.outboundHeaderName = setting.Outbound_Header_Name__c;
        c.outboundHeaderValue = setting.Outbound_Header_Value__c;
        c.outboundAdditionalHeadersJson = setting.Outbound_Additional_Headers_JSON__c;
        c.outboundContentType = setting.Outbound_Content_Type__c;
        c.inboundPayloadConfiguration = setting.Inbound_Payload_Configuration__c;
        c.outboundPayloadConfiguration = setting.Outbound_Payload_Configuration__c;
        c.relatedRecordConfiguration = setting.Related_Record_Configuration__c;
        c.targetObjectApiName = String.isBlank(setting.Target_Object_API_Name__c)
            ? DEFAULT_SUBMISSION_OBJECT_API_NAME
            : setting.Target_Object_API_Name__c.trim();
        c.targetRecordTypeDeveloperName = String.isBlank(setting.Target_Record_Type_Developer_Name__c)
            ? null
            : setting.Target_Record_Type_Developer_Name__c.trim();
        c.syncInboundAndOutbound = setting.Sync_Inbound_And_Outbound__c == null
            ? true
            : setting.Sync_Inbound_And_Outbound__c;
        return c;
    }
}

