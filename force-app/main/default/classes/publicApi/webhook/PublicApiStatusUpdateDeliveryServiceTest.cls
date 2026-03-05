@IsTest
private class PublicApiStatusUpdateDeliveryServiceTest {
    private static Integer metadataCallCount = 0;
    private static Integer webhookCallCount = 0;

    private class MetadataAndWebhookMock implements HttpCalloutMock {
        private Boolean metadataShouldFail;

        MetadataAndWebhookMock(Boolean metadataShouldFail) {
            this.metadataShouldFail = metadataShouldFail;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint() != null && request.getEndpoint().contains('/services/Soap/m/61.0')) {
                metadataCallCount++;
                if (metadataShouldFail) {
                    response.setStatusCode(500);
                    response.setBody('metadata failure');
                    return response;
                }
                response.setStatusCode(200);
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<soapenv:Body>' +
                    '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
                    '<result><success>true</success><fullName>PublicApiWebhook_Webhook</fullName></result>' +
                    '</createMetadataResponse>' +
                    '</soapenv:Body>' +
                    '</soapenv:Envelope>'
                );
                return response;
            }

            webhookCallCount++;
            response.setStatusCode(202);
            response.setStatus('Accepted');
            response.setBody('ok');
            return response;
        }
    }

    @IsTest
    static void testValidateOutboundMappingsRequiresConfiguration() {
        try {
            PublicApiStatusUpdateDeliveryService.validateOutboundMappings(null);
            System.assert(false, 'Expected missing outbound mapping configuration to throw.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('Outbound mapping configuration is required'));
        }
    }

    @IsTest
    static void testValidateOutboundMappingsRejectsInvalidFields() {
        String configJson =
            '{"inbound":[],"outbound":[{"externalKey":"bad","value":"$intakes.Does_Not_Exist__c","sortOrder":1}]}';
        try {
            PublicApiStatusUpdateDeliveryService.validateOutboundMappings(configJson);
            System.assert(false, 'Expected invalid outbound mapping field to throw.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('Unknown field reference'));
        }
    }

    @IsTest
    static void testSendStatusUpdateReturnsFailureForInvalidMappingConfig() {
        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookUrl = 'https://example.com/webhook';
        config.requestFieldMappingsConfiguration = '{ bad json }';

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Email__c = 'delivery@example.com'
        );

        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config);

        System.assertNotEquals(null, outcome);
        System.assertNotEquals(null, outcome.deliveryResult);
        System.assertEquals(false, outcome.deliveryResult.success);
        System.assert(
            String.valueOf(outcome.deliveryResult.exceptionMessage).contains('Unexpected')
            || String.valueOf(outcome.deliveryResult.exceptionMessage).contains('Invalid')
        );
    }

    @IsTest
    static void testSendStatusUpdate_ProvisionsRemoteSiteOncePerDomain() {
        metadataCallCount = 0;
        webhookCallCount = 0;
        PublicApiStatusUpdateDeliveryService.provisionedWebhookDomainsInTransaction.clear();
        Test.setMock(HttpCalloutMock.class, new MetadataAndWebhookMock(false));

        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookUrl = 'https://example.com/webhook';
        config.requestFieldMappingsConfiguration =
            '{"inbound":[],"outbound":[{"externalKey":"email","value":"$intakes.Email__c","sortOrder":1}]}';

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Email__c = 'delivery@example.com'
        );

        Test.startTest();
        PublicApiStatusUpdateDeliveryService.SendOutcome firstOutcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config, 'test-session');
        PublicApiStatusUpdateDeliveryService.SendOutcome secondOutcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config, 'test-session');
        Test.stopTest();

        System.assertEquals(true, firstOutcome.deliveryResult.success);
        System.assertEquals(true, secondOutcome.deliveryResult.success);
        System.assertEquals(1, metadataCallCount, 'Remote site provisioning should happen once per domain per transaction.');
        System.assertEquals(2, webhookCallCount, 'Webhook should still send for each delivery attempt.');
    }

    @IsTest
    static void testSendStatusUpdate_ReturnsFailureWhenProvisioningFails() {
        metadataCallCount = 0;
        webhookCallCount = 0;
        PublicApiStatusUpdateDeliveryService.provisionedWebhookDomainsInTransaction.clear();
        Test.setMock(HttpCalloutMock.class, new MetadataAndWebhookMock(true));

        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookUrl = 'https://example.com/webhook';
        config.requestFieldMappingsConfiguration =
            '{"inbound":[],"outbound":[{"externalKey":"email","value":"$intakes.Email__c","sortOrder":1}]}';

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Email__c = 'delivery@example.com'
        );

        Test.startTest();
        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config, 'test-session');
        Test.stopTest();

        System.assertNotEquals(null, outcome);
        System.assertNotEquals(null, outcome.deliveryResult);
        System.assertEquals(false, outcome.deliveryResult.success);
        System.assert(String.valueOf(outcome.deliveryResult.exceptionMessage).contains('Metadata API callout failed'));
        System.assertEquals(1, metadataCallCount);
        System.assertEquals(0, webhookCallCount, 'Webhook send should not run when provisioning fails.');
    }
}
