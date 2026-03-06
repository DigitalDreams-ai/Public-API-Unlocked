// Create or update an active Public API Integration Config record with a usable API key.
String defaultApiKey = 'dev-publicApi-api-key';
List<PublicApi_Integration_Config__c> existing = [
    SELECT Id, API_Key__c, Is_Active__c, Inbound_Target_Object_API_Name__c, Outbound_Source_Object_API_Name__c
    FROM PublicApi_Integration_Config__c
    WHERE Is_Active__c = true
    ORDER BY CreatedDate DESC
    LIMIT 1
];

if (!existing.isEmpty()) {
    PublicApi_Integration_Config__c config = existing[0];
    Boolean shouldUpdate = false;
    if (String.isBlank(config.API_Key__c)) {
        config.API_Key__c = defaultApiKey;
        shouldUpdate = true;
    }
    if (String.isBlank(config.Inbound_Target_Object_API_Name__c)) {
        config.Inbound_Target_Object_API_Name__c = 'PublicApi_Submission__c';
        shouldUpdate = true;
    }
    if (String.isBlank(config.Outbound_Source_Object_API_Name__c)) {
        config.Outbound_Source_Object_API_Name__c = 'PublicApi_Submission__c';
        shouldUpdate = true;
    }
    if (shouldUpdate) {
        update config;
        System.debug('Public API Integration Config: Updated active config defaults.');
    } else {
        System.debug('Public API Integration Config: Active config already has API key and object defaults.');
    }
} else {
    insert new PublicApi_Integration_Config__c(
        Is_Active__c = true,
        API_Key__c = defaultApiKey,
        Inbound_Target_Object_API_Name__c = 'PublicApi_Submission__c',
        Outbound_Source_Object_API_Name__c = 'PublicApi_Submission__c'
    );
    System.debug('Public API Integration Config: Created active config with API Key = ' + defaultApiKey);
}
