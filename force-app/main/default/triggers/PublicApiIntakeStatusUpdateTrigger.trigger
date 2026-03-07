trigger PublicApiIntakeStatusUpdateTrigger on PublicApi_Submission__c (before update, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        PublicApiStatusUpdateHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        PublicApiStatusUpdateHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
