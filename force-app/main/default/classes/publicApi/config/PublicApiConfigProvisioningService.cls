public without sharing class PublicApiConfigProvisioningService {
    @TestVisible
    static String sessionIdOverride;

    public static PublicApi_Integration_Config__c provisionRemoteSite(Id configId) {
        return provisionRemoteSite(configId, null);
    }

    public static PublicApi_Integration_Config__c provisionRemoteSite(Id configId, String explicitSessionId) {
        if (configId == null) {
            throw new PublicApiRemoteSiteSettingException('Config ID is required.');
        }

        PublicApi_Integration_Config__c record = PublicApiConfigRepository.findById(configId);
        if (record == null) {
            throw new PublicApiRemoteSiteSettingException('Public API Integration Config not found: ' + configId);
        }

        PublicApi_Integration_Config__c updateRecord = buildProvisioningUpdateForRecord(
            record,
            getProvisioningSessionId(explicitSessionId)
        );
        update updateRecord;
        return PublicApiConfigRepository.findById(configId);
    }

    @TestVisible
    static PublicApi_Integration_Config__c buildProvisioningUpdateForRecord(
        PublicApi_Integration_Config__c record,
        String sessionId
    ) {
        if (record == null) {
            return null;
        }

        String currentDomain = PublicApiRemoteSiteSettingService.extractDomainFromUrl(record.Outbound_Webhook_URL__c);
        if (String.isBlank(currentDomain)) {
            return buildProvisioningUpdate(record.Id, null, null, null, null, null);
        }

        try {
            String remoteSiteName =
                PublicApiRemoteSiteSettingService.ensureStatusWebhookRemoteSite(record.Outbound_Webhook_URL__c, sessionId);
            return buildProvisioningUpdate(
                record.Id,
                currentDomain,
                remoteSiteName,
                PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED,
                null,
                System.now()
            );
        } catch (Exception e) {
            return buildProvisioningUpdate(
                record.Id,
                currentDomain,
                PublicApiRemoteSiteSettingService.getRemoteSiteSettingNameForDomain(currentDomain),
                PublicApiConfigService.REMOTE_SITE_STATUS_FAILED,
                truncateError(e.getMessage()),
                null
            );
        }
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

    private static String getProvisioningSessionId(String explicitSessionId) {
        if (String.isNotBlank(explicitSessionId)) {
            return explicitSessionId.trim();
        }
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
