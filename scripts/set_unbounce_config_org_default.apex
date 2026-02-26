// Create or update the active Unbounce Integration Config record so the Unbounce Intake API works in scratch org.
// Uses the first Firm found (from Shulman-Core or test data).
List<litify_pm__Firm__c> firms = [SELECT Id FROM litify_pm__Firm__c LIMIT 1];
if (firms.isEmpty()) {
    System.debug('Unbounce Integration Config: No Firm found; skip setting config.');
} else {
    List<Unbounce_Integration_Config__c> existing = [SELECT Id FROM Unbounce_Integration_Config__c WHERE Is_Active__c = true ORDER BY CreatedDate DESC LIMIT 1];
    if (!existing.isEmpty()) {
        existing[0].Default_Firm_Id__c = firms[0].Id;
        update existing[0];
        System.debug('Unbounce Integration Config: Updated active config Firm Id = ' + firms[0].Id);
    } else {
        Unbounce_Integration_Config__c c = new Unbounce_Integration_Config__c();
        c.Is_Active__c = true;
        c.Default_Firm_Id__c = firms[0].Id;
        insert c;
        System.debug('Unbounce Integration Config: Created config with Firm Id = ' + firms[0].Id);
    }
}
