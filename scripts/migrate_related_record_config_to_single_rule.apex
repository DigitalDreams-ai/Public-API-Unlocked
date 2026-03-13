List<PublicApi_Integration_Config__c> configsToUpdate = new List<PublicApi_Integration_Config__c>();

for (PublicApi_Integration_Config__c configRecord : [
    SELECT Id, Related_Record_Configuration__c
    FROM PublicApi_Integration_Config__c
]) {
    String rawConfig = configRecord.Related_Record_Configuration__c;
    if (String.isBlank(rawConfig)) {
        continue;
    }

    Object parsed;
    try {
        parsed = JSON.deserializeUntyped(rawConfig);
    } catch (Exception e) {
        System.debug('Skipping invalid related-record config on ' + configRecord.Id + ': ' + e.getMessage());
        continue;
    }

    if (!(parsed instanceof List<Object>)) {
        continue;
    }

    List<Object> rules = (List<Object>) parsed;
    Map<String, Object> firstRule = null;
    for (Object entry : rules) {
        if (entry instanceof Map<String, Object>) {
            firstRule = (Map<String, Object>) entry;
            break;
        }
    }

    configRecord.Related_Record_Configuration__c =
        firstRule == null ? null : JSON.serialize(firstRule);
    configsToUpdate.add(configRecord);
}

if (!configsToUpdate.isEmpty()) {
    update configsToUpdate;
}

System.debug('Migrated related-record config rows: ' + configsToUpdate.size());
