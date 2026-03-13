// Create or update an active Public API Integration Config record with a usable API key.
String defaultApiKey = 'dev-publicApi-api-key';
List<PublicApi_Integration_Config__c> existing = [
    SELECT Id,
           API_Key__c,
           Is_Active__c,
           Target_Object_API_Name__c,
           Sync_Inbound_And_Outbound__c,
           Outbound_Trigger_Field_Name__c,
           Outbound_Trigger_Field_Values__c,
           Outbound_Trigger_Enabled__c
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
    if (String.isBlank(config.Target_Object_API_Name__c)) {
        config.Target_Object_API_Name__c = 'PublicApi_Submission__c';
        shouldUpdate = true;
    }
    if (config.Sync_Inbound_And_Outbound__c == null) {
        config.Sync_Inbound_And_Outbound__c = true;
        shouldUpdate = true;
    }
    if (config.Outbound_Trigger_Enabled__c == null) {
        config.Outbound_Trigger_Enabled__c = true;
        shouldUpdate = true;
    }
    if (String.isBlank(config.Outbound_Trigger_Field_Name__c)) {
        config.Outbound_Trigger_Field_Name__c = 'Status__c';
        shouldUpdate = true;
    }
    if (String.isBlank(config.Outbound_Trigger_Field_Values__c)) {
        config.Outbound_Trigger_Field_Values__c = 'Referred Out,Converted';
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
        Target_Object_API_Name__c = 'PublicApi_Submission__c',
        Sync_Inbound_And_Outbound__c = true,
        Outbound_Trigger_Field_Name__c = 'Status__c',
        Outbound_Trigger_Field_Values__c = 'Referred Out,Converted',
        Outbound_Trigger_Enabled__c = true
    );
    System.debug('Public API Integration Config: Created active config with API Key = ' + defaultApiKey);
}
