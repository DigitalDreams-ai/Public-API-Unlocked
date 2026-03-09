@IsTest
public class PublicApiTestConfigFactory {
    public static PublicApi_Integration_Config__c insertConfig(PublicApi_Integration_Config__c config) {
        PublicApiConfigProvisioningService.bypassTrigger = true;
        try {
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
        } finally {
            PublicApiConfigProvisioningService.bypassTrigger = false;
        }
        return config;
    }
}
