// Set Unbounce Config org default so the Unbounce Intake API works in scratch org.
// Uses the first Firm found (from Shulman-Core or test data).
List<litify_pm__Firm__c> firms = [SELECT Id FROM litify_pm__Firm__c LIMIT 1];
if (firms.isEmpty()) {
    System.debug('Unbounce Config: No Firm found; skip setting org default.');
} else {
    Unbounce_Config__c c = new Unbounce_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
    c.Default_Firm_Id__c = firms[0].Id;
    upsert c;
    System.debug('Unbounce Config: Set org default Firm Id = ' + firms[0].Id);
}
