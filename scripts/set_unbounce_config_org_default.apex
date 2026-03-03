// Create or update an active Unbounce Integration Config record with a usable API key.
String defaultApiKey = 'dev-unbounce-api-key';
List<Unbounce_Integration_Config__c> existing = [
    SELECT Id, API_Key__c, Is_Active__c
    FROM Unbounce_Integration_Config__c
    WHERE Is_Active__c = true
    ORDER BY CreatedDate DESC
    LIMIT 1
];

if (!existing.isEmpty()) {
    Unbounce_Integration_Config__c config = existing[0];
    if (String.isBlank(config.API_Key__c)) {
        config.API_Key__c = defaultApiKey;
        update config;
        System.debug('Unbounce Integration Config: Updated active config API Key = ' + defaultApiKey);
    } else {
        System.debug('Unbounce Integration Config: Active config already has API Key = ' + config.API_Key__c);
    }
} else {
    insert new Unbounce_Integration_Config__c(
        Is_Active__c = true,
        API_Key__c = defaultApiKey
    );
    System.debug('Unbounce Integration Config: Created active config with API Key = ' + defaultApiKey);
}
