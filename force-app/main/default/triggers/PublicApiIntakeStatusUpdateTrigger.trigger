trigger PublicApiIntakeStatusUpdateTrigger on PublicApi_Submission__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        PublicApiStatusUpdateHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
