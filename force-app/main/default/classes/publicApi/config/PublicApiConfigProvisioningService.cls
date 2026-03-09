public without sharing class PublicApiConfigProvisioningService {
    @TestVisible
    static Boolean bypassTrigger = false;
    @TestVisible
    static String sessionIdOverride;

    public static void prepareProvisioningState(
        List<PublicApi_Integration_Config__c> newRecords,
        Map<Id, PublicApi_Integration_Config__c> oldMap
    ) {
        if (bypassTrigger || newRecords == null || newRecords.isEmpty()) {
            return;
        }

        for (PublicApi_Integration_Config__c newRecord : newRecords) {
            if (newRecord == null) {
                continue;
            }

            String currentDomain = PublicApiRemoteSiteSettingService.extractDomainFromUrl(
                newRecord.Outbound_Webhook_URL__c
            );
            PublicApi_Integration_Config__c oldRecord =
                oldMap == null ? null : oldMap.get(newRecord.Id);
            String previousDomain = oldRecord == null
                ? null
                : PublicApiRemoteSiteSettingService.extractDomainFromUrl(oldRecord.Outbound_Webhook_URL__c);

            if (String.isBlank(currentDomain)) {
                clearProvisioningState(newRecord);
                continue;
            }

            newRecord.Outbound_Remote_Site_Domain__c = currentDomain;
            newRecord.Outbound_Remote_Site_Name__c =
                PublicApiRemoteSiteSettingService.getRemoteSiteSettingNameForDomain(currentDomain);

            Boolean shouldResetState = oldRecord == null ||
                !equalsIgnoreCase(currentDomain, previousDomain) ||
                oldRecord.Outbound_Remote_Site_Status__c != PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED;
            if (shouldResetState) {
                newRecord.Outbound_Remote_Site_Status__c = PublicApiConfigService.REMOTE_SITE_STATUS_PENDING;
                newRecord.Outbound_Remote_Site_Last_Error__c = null;
                newRecord.Outbound_Remote_Site_Last_Provisioned_At__c = null;
            }
        }
    }

    public static void enqueueProvisioning(
        List<PublicApi_Integration_Config__c> newRecords,
        Map<Id, PublicApi_Integration_Config__c> oldMap
    ) {
        if (bypassTrigger || newRecords == null || newRecords.isEmpty()) {
            return;
        }

        List<Id> configIdsToProvision = new List<Id>();
        for (PublicApi_Integration_Config__c newRecord : newRecords) {
            if (shouldQueueProvisioning(newRecord, oldMap == null ? null : oldMap.get(newRecord.Id))) {
                configIdsToProvision.add(newRecord.Id);
            }
        }
        if (configIdsToProvision.isEmpty()) {
            return;
        }

        provisionRemoteSitesAsync(configIdsToProvision, getProvisioningSessionId());
    }

    @future(callout=true)
    public static void provisionRemoteSitesAsync(List<Id> configIds, String sessionId) {
        if (configIds == null || configIds.isEmpty()) {
            return;
        }

        List<PublicApi_Integration_Config__c> updates = new List<PublicApi_Integration_Config__c>();
        List<PublicApi_Integration_Config__c> records =
            PublicApiConfigRepository.findActiveByIds(new Set<Id>(configIds));
        for (PublicApi_Integration_Config__c record : records) {
            String currentDomain = PublicApiRemoteSiteSettingService.extractDomainFromUrl(record.Outbound_Webhook_URL__c);
            if (String.isBlank(currentDomain)) {
                updates.add(buildProvisioningUpdate(record.Id, null, null, null, null, null));
                continue;
            }

            try {
                String remoteSiteName =
                    PublicApiRemoteSiteSettingService.ensureStatusWebhookRemoteSite(record.Outbound_Webhook_URL__c, sessionId);
                updates.add(buildProvisioningUpdate(
                    record.Id,
                    currentDomain,
                    remoteSiteName,
                    PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED,
                    null,
                    System.now()
                ));
            } catch (Exception e) {
                updates.add(buildProvisioningUpdate(
                    record.Id,
                    currentDomain,
                    PublicApiRemoteSiteSettingService.getRemoteSiteSettingNameForDomain(currentDomain),
                    PublicApiConfigService.REMOTE_SITE_STATUS_FAILED,
                    truncateError(e.getMessage()),
                    null
                ));
            }
        }

        if (!updates.isEmpty()) {
            bypassTrigger = true;
            try {
                update updates;
            } finally {
                bypassTrigger = false;
            }
        }
    }

    @TestVisible
    static Boolean shouldQueueProvisioning(
        PublicApi_Integration_Config__c newRecord,
        PublicApi_Integration_Config__c oldRecord
    ) {
        if (newRecord == null ||
            newRecord.Is_Active__c != true ||
            String.isBlank(newRecord.Outbound_Webhook_URL__c)) {
            return false;
        }

        String currentDomain = PublicApiRemoteSiteSettingService.extractDomainFromUrl(newRecord.Outbound_Webhook_URL__c);
        if (String.isBlank(currentDomain) ||
            newRecord.Outbound_Remote_Site_Status__c != PublicApiConfigService.REMOTE_SITE_STATUS_PENDING) {
            return false;
        }

        if (oldRecord == null) {
            return true;
        }

        String previousDomain = PublicApiRemoteSiteSettingService.extractDomainFromUrl(oldRecord.Outbound_Webhook_URL__c);
        if (!equalsIgnoreCase(currentDomain, previousDomain)) {
            return true;
        }

        return oldRecord.Outbound_Remote_Site_Status__c != PublicApiConfigService.REMOTE_SITE_STATUS_PENDING;
    }

    @TestVisible
    static PublicApi_Integration_Config__c buildProvisioningUpdate(
        Id configId,
        String domain,
        String remoteSiteName,
        String status,
        String lastError,
        Datetime lastProvisionedAt
    ) {
        return new PublicApi_Integration_Config__c(
            Id = configId,
            Outbound_Remote_Site_Domain__c = domain,
            Outbound_Remote_Site_Name__c = remoteSiteName,
            Outbound_Remote_Site_Status__c = status,
            Outbound_Remote_Site_Last_Error__c = lastError,
            Outbound_Remote_Site_Last_Provisioned_At__c = lastProvisionedAt
        );
    }

    @TestVisible
    static void clearProvisioningState(PublicApi_Integration_Config__c record) {
        if (record == null) {
            return;
        }
        record.Outbound_Remote_Site_Domain__c = null;
        record.Outbound_Remote_Site_Name__c = null;
        record.Outbound_Remote_Site_Status__c = null;
        record.Outbound_Remote_Site_Last_Error__c = null;
        record.Outbound_Remote_Site_Last_Provisioned_At__c = null;
    }

    private static Boolean equalsIgnoreCase(String left, String right) {
        if (left == null || right == null) {
            return left == right;
        }
        return left.trim().toLowerCase() == right.trim().toLowerCase();
    }

    private static String getProvisioningSessionId() {
        if (Test.isRunningTest() && String.isNotBlank(sessionIdOverride)) {
            return sessionIdOverride;
        }
        return UserInfo.getSessionId();
    }

    private static String truncateError(String message) {
        if (String.isBlank(message)) {
            return message;
        }
        return message.length() > 32768 ? message.substring(0, 32768) : message;
    }
}
