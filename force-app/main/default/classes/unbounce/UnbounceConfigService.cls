/**
 * Resolves Unbounce configuration from the Unbounce Integration Config custom object.
 * Create at least one Unbounce_Integration_Config__c record and set Is_Active__c = true.
 * getConfig() returns the most recently created active record.
 */
public with sharing class UnbounceConfigService {

    public class Config {
        public String webhookSecret;
        public String apiKey;
        public String referredByPartyName;
    }

    public static Config getConfig() {
        List<Unbounce_Integration_Config__c> settings = [
            SELECT Webhook_Secret__c, API_Key__c, Referred_By_Party_Name__c
            FROM Unbounce_Integration_Config__c
            WHERE Is_Active__c = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (settings.isEmpty()) {
            return null;
        }
        Unbounce_Integration_Config__c setting = settings[0];

        Config c = new Config();
        c.webhookSecret = setting.Webhook_Secret__c;
        c.apiKey = setting.API_Key__c;
        c.referredByPartyName = setting.Referred_By_Party_Name__c;
        return c;
    }
}
