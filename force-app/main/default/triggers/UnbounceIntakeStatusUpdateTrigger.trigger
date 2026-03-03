trigger UnbounceIntakeStatusUpdateTrigger on litify_pm__Intake__c (before update, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        UnbounceIntakeStatusUpdateTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        UnbounceIntakeStatusUpdateTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
