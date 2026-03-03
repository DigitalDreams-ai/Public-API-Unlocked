trigger UnbounceIntakeStatusUpdateTrigger on litify_pm__Intake__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        UnbounceIntakeStatusUpdateTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
