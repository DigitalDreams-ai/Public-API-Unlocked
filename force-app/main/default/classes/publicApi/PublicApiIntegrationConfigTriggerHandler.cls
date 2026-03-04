public without sharing class PublicApiIntegrationConfigTriggerHandler {
    @TestVisible
    private static Boolean enableRemoteSiteProvisioningInTests = false;

    public static void handleAfterInsert(List<PublicApi_Integration_Config__c> newConfigs) {
        enqueueRemoteSiteCreation(newConfigs, null);
    }

    public static void handleAfterUpdate(
        List<PublicApi_Integration_Config__c> newConfigs,
        Map<Id, PublicApi_Integration_Config__c> oldMap
    ) {
        enqueueRemoteSiteCreation(newConfigs, oldMap);
    }

    private static void enqueueRemoteSiteCreation(
        List<PublicApi_Integration_Config__c> newConfigs,
        Map<Id, PublicApi_Integration_Config__c> oldMap
    ) {
        if (Test.isRunningTest() && !enableRemoteSiteProvisioningInTests) {
            return;
        }
        if (newConfigs == null || newConfigs.isEmpty()) {
            return;
        }

        Set<String> webhookUrls = new Set<String>();
        for (PublicApi_Integration_Config__c newConfig : newConfigs) {
            if (!shouldProvisionRemoteSite(newConfig, oldMap != null ? oldMap.get(newConfig.Id) : null)) {
                continue;
            }
            webhookUrls.add(newConfig.Outbound_Webhook_URL__c.trim());
        }

        if (!webhookUrls.isEmpty()) {
            PublicApiRemoteSiteSettingService.ensureStatusWebhookRemoteSitesAsync(
                new List<String>(webhookUrls)
            );
        }
    }

    @TestVisible
    private static Boolean shouldProvisionRemoteSite(
        PublicApi_Integration_Config__c newConfig,
        PublicApi_Integration_Config__c oldConfig
    ) {
        if (newConfig == null || String.isBlank(newConfig.Outbound_Webhook_URL__c)) {
            return false;
        }
        if (oldConfig == null) {
            return true;
        }
        return normalizeUrl(newConfig.Outbound_Webhook_URL__c) !=
            normalizeUrl(oldConfig.Outbound_Webhook_URL__c);
    }

    private static String normalizeUrl(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
