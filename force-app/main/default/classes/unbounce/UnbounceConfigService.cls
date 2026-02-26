/**
 * Resolves Unbounce configuration from Custom Setting.
 * Set org default via Setup > Custom Settings > Unbounce Config > Manage.
 */
public with sharing class UnbounceConfigService {

    public class Config {
        public Id defaultFirmId;
        public String defaultCaseTypeName;
        public String webhookSecret;
        public String apiKey;
    }

    public static Config getConfig() {
        Unbounce_Config__c setting = Unbounce_Config__c.getOrgDefaults();
        if (setting == null || String.isBlank(setting.Default_Firm_Id__c)) {
            return null;
        }

        Config c = new Config();
        c.defaultFirmId = Id.valueOf(setting.Default_Firm_Id__c.trim());
        c.defaultCaseTypeName = setting.Default_Case_Type_Name__c;
        c.webhookSecret = setting.Webhook_Secret__c;
        c.apiKey = setting.API_Key__c;
        return c;
    }
}
