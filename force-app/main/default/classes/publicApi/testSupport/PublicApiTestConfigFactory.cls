@IsTest
public class PublicApiTestConfigFactory {
    public static String getDefaultEndpointPathForApiKey(String apiKey) {
        String normalized = String.isBlank(apiKey) ? 'default' : apiKey.trim().toLowerCase();
        normalized = normalized.replaceAll('[^a-z0-9]+', '-');
        normalized = normalized.replaceAll('^-+', '').replaceAll('-+$', '');
        if (String.isBlank(normalized)) {
            normalized = 'default';
        }
        return '/test-' + normalized;
    }

    public static PublicApi_Integration_Config__c insertConfig(PublicApi_Integration_Config__c config) {
        if (config != null && String.isBlank(config.Endpoint_Path__c)) {
            config.Endpoint_Path__c = getDefaultEndpointPathForApiKey(config.API_Key__c);
        }
        if (config != null && String.isNotBlank(config.Outbound_Webhook_URL__c)) {
            String domain = PublicApiRemoteSiteSettingService.extractDomainFromUrl(config.Outbound_Webhook_URL__c);
            config.Outbound_Remote_Site_Domain__c = domain;
            config.Outbound_Remote_Site_Name__c = String.isBlank(domain)
                ? null
                : PublicApiRemoteSiteSettingService.getRemoteSiteSettingNameForDomain(domain);
            config.Outbound_Remote_Site_Status__c = String.isBlank(domain)
                ? null
                : PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED;
            config.Outbound_Remote_Site_Last_Error__c = null;
            config.Outbound_Remote_Site_Last_Provisioned_At__c = String.isBlank(domain)
                ? null
                : System.now();
        }
        insert config;
        return config;
    }
}
