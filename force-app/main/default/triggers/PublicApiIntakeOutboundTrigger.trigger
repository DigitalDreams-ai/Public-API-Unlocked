trigger PublicApiIntakeOutboundTrigger on litify_pm__Intake__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        PublicApiStatusUpdateHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
