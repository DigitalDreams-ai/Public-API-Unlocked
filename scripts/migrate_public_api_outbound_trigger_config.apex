Map<String, Schema.SObjectField> fieldMap =
    PublicApi_Integration_Config__c.SObjectType.getDescribe().fields.getMap();

Boolean hasLegacyTriggerValuesField = fieldMap.containsKey('Outbound_Trigger_Status_Values__c');
Boolean hasLegacyTriggerFieldName = fieldMap.containsKey('Outbound_Trigger_Field_API_Name__c');
Boolean hasNewTriggerFieldName = fieldMap.containsKey('Outbound_Trigger_Field_Name__c');
if (!hasLegacyTriggerValuesField && !hasLegacyTriggerFieldName) {
    System.debug('Legacy outbound trigger fields do not exist. No migration is needed.');
    return;
}

List<SObject> configs = Database.query(
    'SELECT Id, Outbound_Trigger_Field_Name__c, Outbound_Trigger_Field_API_Name__c, Outbound_Trigger_Field_Values__c, Outbound_Trigger_Status_Values__c ' +
    'FROM PublicApi_Integration_Config__c'
);

List<PublicApi_Integration_Config__c> updates = new List<PublicApi_Integration_Config__c>();
for (SObject rawConfig : configs) {
    PublicApi_Integration_Config__c config = (PublicApi_Integration_Config__c) rawConfig;
    Boolean shouldUpdate = false;

    String legacyTriggerFieldName = hasLegacyTriggerFieldName
        ? (String) rawConfig.get('Outbound_Trigger_Field_API_Name__c')
        : null;
    if (hasNewTriggerFieldName && String.isBlank(config.Outbound_Trigger_Field_Name__c)) {
        config.Outbound_Trigger_Field_Name__c = String.isBlank(legacyTriggerFieldName)
            ? 'Status__c'
            : legacyTriggerFieldName;
        shouldUpdate = true;
    }

    String legacyValues = (String) rawConfig.get('Outbound_Trigger_Status_Values__c');
    if (String.isBlank(config.Outbound_Trigger_Field_Values__c) && String.isNotBlank(legacyValues)) {
        config.Outbound_Trigger_Field_Values__c = legacyValues;
        shouldUpdate = true;
    }

    if (shouldUpdate) {
        updates.add(config);
    }
}

if (!updates.isEmpty()) {
    update updates;
    System.debug('Migrated Public API outbound trigger config records: ' + updates.size());
} else {
    System.debug('No Public API outbound trigger config updates were needed.');
}
