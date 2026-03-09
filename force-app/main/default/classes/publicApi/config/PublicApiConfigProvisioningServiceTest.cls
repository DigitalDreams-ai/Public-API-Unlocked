@IsTest
private class PublicApiConfigProvisioningServiceTest {
    private class MetadataApiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        MetadataApiMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    @IsTest
    static void testInsertQueuesProvisioningAndMarksConfigProvisioned() {
        PublicApiConfigProvisioningService.sessionIdOverride = 'test-session-id';
        Test.setMock(HttpCalloutMock.class, new MetadataApiMock(200, metadataApiSuccess('PublicApiWebhook_Example')));

        Test.startTest();
        insert new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'provision-config-key-1',
            Outbound_Webhook_URL__c = 'https://example.com/webhook'
        );
        Test.stopTest();

        PublicApi_Integration_Config__c config = [
            SELECT Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c
            FROM PublicApi_Integration_Config__c
            WHERE API_Key__c = 'provision-config-key-1'
            LIMIT 1
        ];

        System.assertEquals('https://example.com', config.Outbound_Remote_Site_Domain__c);
        System.assertEquals('PublicApiWebhook_Example', config.Outbound_Remote_Site_Name__c);
        System.assertEquals(
            PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED,
            config.Outbound_Remote_Site_Status__c
        );
        System.assertEquals(null, config.Outbound_Remote_Site_Last_Error__c);
        System.assertNotEquals(null, config.Outbound_Remote_Site_Last_Provisioned_At__c);
        PublicApiConfigProvisioningService.sessionIdOverride = null;
    }

    @IsTest
    static void testSaveAfterFailedProvisioningRequeuesAndClearsError() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'provision-config-key-2',
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Remote_Site_Domain__c = 'https://example.com',
            Outbound_Remote_Site_Name__c = 'PublicApiWebhook_Example',
            Outbound_Remote_Site_Status__c = PublicApiConfigService.REMOTE_SITE_STATUS_FAILED,
            Outbound_Remote_Site_Last_Error__c = 'old error'
        );
        PublicApiTestConfigFactory.insertConfig(config);
        update new PublicApi_Integration_Config__c(
            Id = config.Id,
            Outbound_Remote_Site_Status__c = PublicApiConfigService.REMOTE_SITE_STATUS_FAILED,
            Outbound_Remote_Site_Last_Error__c = 'old error'
        );

        PublicApiConfigProvisioningService.sessionIdOverride = 'test-session-id';
        Test.setMock(HttpCalloutMock.class, new MetadataApiMock(200, metadataApiSuccess('PublicApiWebhook_Example')));

        Test.startTest();
        update new PublicApi_Integration_Config__c(
            Id = config.Id,
            API_Key__c = 'provision-config-key-2b'
        );
        Test.stopTest();

        PublicApi_Integration_Config__c updated = [
            SELECT API_Key__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :config.Id
        ];

        System.assertEquals('provision-config-key-2b', updated.API_Key__c);
        System.assertEquals(
            PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED,
            updated.Outbound_Remote_Site_Status__c
        );
        System.assertEquals(null, updated.Outbound_Remote_Site_Last_Error__c);
        System.assertNotEquals(null, updated.Outbound_Remote_Site_Last_Provisioned_At__c);
        PublicApiConfigProvisioningService.sessionIdOverride = null;
    }

    @IsTest
    static void testBlankWebhookClearsProvisioningState() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'provision-config-key-3',
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Remote_Site_Domain__c = 'https://example.com',
            Outbound_Remote_Site_Name__c = 'PublicApiWebhook_Example',
            Outbound_Remote_Site_Status__c = PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED,
            Outbound_Remote_Site_Last_Error__c = null,
            Outbound_Remote_Site_Last_Provisioned_At__c = System.now()
        );
        PublicApiTestConfigFactory.insertConfig(config);

        update new PublicApi_Integration_Config__c(
            Id = config.Id,
            Outbound_Webhook_URL__c = null
        );

        PublicApi_Integration_Config__c updated = [
            SELECT Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :config.Id
        ];

        System.assertEquals(null, updated.Outbound_Remote_Site_Domain__c);
        System.assertEquals(null, updated.Outbound_Remote_Site_Name__c);
        System.assertEquals(null, updated.Outbound_Remote_Site_Status__c);
        System.assertEquals(null, updated.Outbound_Remote_Site_Last_Error__c);
        System.assertEquals(null, updated.Outbound_Remote_Site_Last_Provisioned_At__c);
    }

    private static String metadataApiSuccess(String fullName) {
        return '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
            '<soapenv:Body>' +
            '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
            '<result>' +
            '<success>true</success>' +
            '<fullName>' + fullName + '</fullName>' +
            '</result>' +
            '</createMetadataResponse>' +
            '</soapenv:Body>' +
            '</soapenv:Envelope>';
    }
}
