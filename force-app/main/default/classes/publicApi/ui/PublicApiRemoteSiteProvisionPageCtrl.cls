public with sharing class PublicApiRemoteSiteProvisionPageCtrl {
    public String recordId {
        get {
            return ApexPages.currentPage().getParameters().get('id');
        }
    }

    public String returnUrl {
        get {
            String value = ApexPages.currentPage().getParameters().get('retURL');
            return String.isBlank(value) ? '/lightning/o/PublicApi_Integration_Config__c/list' : value;
        }
    }

    @RemoteAction
    public static Map<String, Object> provision(String recordId, String sessionId) {
        Map<String, Object> response = new Map<String, Object>{
            'success' => false
        };

        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required.');
            }

            PublicApi_Integration_Config__c config =
                PublicApiConfigProvisioningService.provisionRemoteSite((Id) recordId, sessionId);
            response.put('success', true);
            response.put('status', config.Outbound_Remote_Site_Status__c);
            response.put('message', 'Remote site provisioning completed.');
        } catch (Exception e) {
            response.put('message', e.getMessage());
        }

        return response;
    }
}
