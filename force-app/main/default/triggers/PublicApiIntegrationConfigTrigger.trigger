trigger PublicApiIntegrationConfigTrigger on PublicApi_Integration_Config__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            PublicApiIntegrationConfigTriggerHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PublicApiIntegrationConfigTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
