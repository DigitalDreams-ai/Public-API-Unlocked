@IsTest
private class UnbounceConfigTriggerTest {
    private static List<HttpRequest> capturedRequests = new List<HttpRequest>();

    private class MetadataApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            capturedRequests.add(request);
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                '<soapenv:Body>' +
                '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
                '<result><success>true</success><fullName>UnbounceWebhook_Webhook</fullName></result>' +
                '</createMetadataResponse>' +
                '</soapenv:Body>' +
                '</soapenv:Envelope>'
            );
            return response;
        }
    }

    @IsTest
    static void testInsertConfig_WithStatusWebhookUrl_QueuesRemoteSiteCreation() {
        capturedRequests.clear();
        UnbounceIntegrationConfigTriggerHandler.enableRemoteSiteProvisioningInTests = true;
        Test.setMock(HttpCalloutMock.class, new MetadataApiMock());

        Test.startTest();
        insert new Unbounce_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'trigger-test-key-1',
            Outbound_Webhook_URL__c = 'https://webhook.site/4ac60226-8980-4dea-8e8f-a458f9ef9ec5'
        );
        Test.stopTest();
        UnbounceIntegrationConfigTriggerHandler.enableRemoteSiteProvisioningInTests = false;

        System.assertEquals(1, capturedRequests.size());
        System.assert(capturedRequests[0].getBody().contains('<met:url>https://webhook.site</met:url>'));
    }

    @IsTest
    static void testUpdateConfig_UnchangedStatusWebhookUrl_DoesNotQueueRemoteSiteCreation() {
        capturedRequests.clear();
        UnbounceIntegrationConfigTriggerHandler.enableRemoteSiteProvisioningInTests = true;
        insert new Unbounce_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'trigger-test-key-2'
        );

        Test.setMock(HttpCalloutMock.class, new MetadataApiMock());

        Test.startTest();
        update new Unbounce_Integration_Config__c(
            Id = [SELECT Id FROM Unbounce_Integration_Config__c WHERE API_Key__c = 'trigger-test-key-2' LIMIT 1].Id,
            Referred_By_Party_Name__c = 'PMAX-Unbounce'
        );
        Test.stopTest();
        UnbounceIntegrationConfigTriggerHandler.enableRemoteSiteProvisioningInTests = false;

        System.assertEquals(0, capturedRequests.size());
    }

    @IsTest
    static void testShouldProvisionRemoteSite_WhenUrlChanges() {
        System.assertEquals(
            true,
            UnbounceIntegrationConfigTriggerHandler.shouldProvisionRemoteSite(
                new Unbounce_Integration_Config__c(Outbound_Webhook_URL__c = 'https://webhook.site/new'),
                new Unbounce_Integration_Config__c(Outbound_Webhook_URL__c = 'https://example.com/old')
            )
        );
        System.assertEquals(
            false,
            UnbounceIntegrationConfigTriggerHandler.shouldProvisionRemoteSite(
                new Unbounce_Integration_Config__c(Outbound_Webhook_URL__c = 'https://webhook.site/new'),
                new Unbounce_Integration_Config__c(Outbound_Webhook_URL__c = 'https://webhook.site/new')
            )
        );
    }
}
