List<PublicApi_Webhook_Delivery__c> updates = new List<PublicApi_Webhook_Delivery__c>();

for (PublicApi_Webhook_Delivery__c delivery : [
    SELECT Id, Submission__c, Source_Record_Id__c, Source_Object_API_Name__c
    FROM PublicApi_Webhook_Delivery__c
    WHERE Submission__c = null
      AND Source_Object_API_Name__c = 'PublicApi_Submission__c'
      AND Source_Record_Id__c != null
]) {
    updates.add(
        new PublicApi_Webhook_Delivery__c(
            Id = delivery.Id,
            Submission__c = delivery.Source_Record_Id__c
        )
    );
}

if (!updates.isEmpty()) {
    Database.SaveResult[] results = Database.update(updates, false);
    Integer successCount = 0;
    Integer failureCount = 0;
    for (Database.SaveResult result : results) {
        if (result.isSuccess()) {
            successCount++;
        } else {
            failureCount++;
            System.debug('Failed to backfill PublicApi_Webhook_Delivery__c.Submission__c: ' + result.getErrors()[0].getMessage());
        }
    }
    System.debug('Backfilled PublicApi_Webhook_Delivery__c.Submission__c. Success=' + successCount + ', Fail=' + failureCount);
} else {
    System.debug('No PublicApi_Webhook_Delivery__c rows required Submission__c backfill.');
}
