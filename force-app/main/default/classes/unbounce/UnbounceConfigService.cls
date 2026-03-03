/**
 * Resolves Unbounce configuration from the Unbounce Integration Config custom object.
 * Exactly one Unbounce_Integration_Config__c record should be active at a time.
 */
public without sharing class UnbounceConfigService {

    public class Config {
        public String webhookSecret;
        public String apiKey;
        public String referredByPartyName;
    }

    public static Config getConfig() {
        List<Unbounce_Integration_Config__c> settings = [
            SELECT Id, Webhook_Secret__c, API_Key__c, Referred_By_Party_Name__c
            FROM Unbounce_Integration_Config__c
            WHERE Is_Active__c = true
            ORDER BY CreatedDate DESC
            LIMIT 2
        ];
        if (settings.isEmpty()) {
            return null;
        }
        if (settings.size() > 1) {
            throw new UnbounceIntakeServiceException(
                'Unbounce integration is misconfigured. Exactly one active Unbounce Integration Config record is required.'
            );
        }
        Unbounce_Integration_Config__c setting = settings[0];

        Config c = new Config();
        c.webhookSecret = setting.Webhook_Secret__c;
        c.apiKey = setting.API_Key__c;
        c.referredByPartyName = setting.Referred_By_Party_Name__c;
        return c;
    }
}
