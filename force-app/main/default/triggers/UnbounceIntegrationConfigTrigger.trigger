trigger UnbounceIntegrationConfigTrigger on Unbounce_Integration_Config__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            UnbounceIntegrationConfigTriggerHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            UnbounceIntegrationConfigTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
