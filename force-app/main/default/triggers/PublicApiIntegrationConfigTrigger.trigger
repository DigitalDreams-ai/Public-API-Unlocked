trigger PublicApiIntegrationConfigTrigger on PublicApi_Integration_Config__c (
    before insert,
    before update,
    after insert,
    after update
) {
    if (Trigger.isBefore) {
        PublicApiConfigProvisioningService.prepareProvisioningState(
            Trigger.new,
            Trigger.isInsert ? null : Trigger.oldMap
        );
        return;
    }

    PublicApiConfigProvisioningService.enqueueProvisioning(
        Trigger.new,
        Trigger.isInsert ? null : Trigger.oldMap
    );
}
