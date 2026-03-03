public without sharing class UnbounceIntegrationConfigTriggerHandler {
    @TestVisible
    private static Boolean enableRemoteSiteProvisioningInTests = false;

    public static void handleAfterInsert(List<Unbounce_Integration_Config__c> newConfigs) {
        enqueueRemoteSiteCreation(newConfigs, null);
    }

    public static void handleAfterUpdate(
        List<Unbounce_Integration_Config__c> newConfigs,
        Map<Id, Unbounce_Integration_Config__c> oldMap
    ) {
        enqueueRemoteSiteCreation(newConfigs, oldMap);
    }

    private static void enqueueRemoteSiteCreation(
        List<Unbounce_Integration_Config__c> newConfigs,
        Map<Id, Unbounce_Integration_Config__c> oldMap
    ) {
        if (Test.isRunningTest() && !enableRemoteSiteProvisioningInTests) {
            return;
        }
        if (newConfigs == null || newConfigs.isEmpty()) {
            return;
        }

        Set<String> webhookUrls = new Set<String>();
        for (Unbounce_Integration_Config__c newConfig : newConfigs) {
            if (!shouldProvisionRemoteSite(newConfig, oldMap != null ? oldMap.get(newConfig.Id) : null)) {
                continue;
            }
            webhookUrls.add(newConfig.Status_Update_Webhook_URL__c.trim());
        }

        if (!webhookUrls.isEmpty()) {
            UnbounceRemoteSiteSettingService.ensureStatusWebhookRemoteSitesAsync(
                new List<String>(webhookUrls)
            );
        }
    }

    @TestVisible
    private static Boolean shouldProvisionRemoteSite(
        Unbounce_Integration_Config__c newConfig,
        Unbounce_Integration_Config__c oldConfig
    ) {
        if (newConfig == null || String.isBlank(newConfig.Status_Update_Webhook_URL__c)) {
            return false;
        }
        if (oldConfig == null) {
            return true;
        }
        return normalizeUrl(newConfig.Status_Update_Webhook_URL__c) !=
            normalizeUrl(oldConfig.Status_Update_Webhook_URL__c);
    }

    private static String normalizeUrl(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
