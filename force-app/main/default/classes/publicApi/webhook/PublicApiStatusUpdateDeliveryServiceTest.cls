@IsTest
private class PublicApiStatusUpdateDeliveryServiceTest {
    private static Integer webhookCallCount = 0;

    private class WebhookOnlyMock implements HttpCalloutMock {
        private Integer webhookStatusCode;

        WebhookOnlyMock(Integer webhookStatusCode) {
            this.webhookStatusCode = webhookStatusCode;
        }

        public HttpResponse respond(HttpRequest request) {
            webhookCallCount++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(webhookStatusCode);
            response.setStatus(webhookStatusCode == 202 ? 'Accepted' : 'Error');
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
            '[{"externalKey":"bad","value":"$PublicApi_Submission__c.Does_Not_Exist__c","sortOrder":1}]';
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
        config.targetObjectApiName = 'PublicApi_Submission__c';
        config.outboundPayloadConfiguration = '{ bad json }';
        config.outboundRemoteSiteDomain = 'https://example.com';
        config.outboundRemoteSiteStatus = PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'Converted'
        );

        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config);

        System.assertNotEquals(null, outcome);
        System.assertNotEquals(null, outcome.deliveryResult);
        System.assertEquals(false, outcome.deliveryResult.success);
        System.assertEquals(
            PublicApiStatusUpdateDeliveryService.ERROR_CODE_MAPPING_ERROR,
            outcome.deliveryResult.errorCode
        );
    }

    @IsTest
    static void testSendStatusUpdate_SendsWhenRemoteSiteProvisioned() {
        webhookCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new WebhookOnlyMock(202));

        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookUrl = 'https://example.com/webhook';
        config.targetObjectApiName = 'PublicApi_Submission__c';
        config.outboundPayloadConfiguration =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';
        config.outboundRemoteSiteDomain = 'https://example.com';
        config.outboundRemoteSiteStatus = PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'Converted'
        );

        Test.startTest();
        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config);
        Test.stopTest();

        System.assertEquals(true, outcome.deliveryResult.success);
        System.assertEquals(1, webhookCallCount);
    }

    @IsTest
    static void testSendStatusUpdate_ReturnsFailureWhenRemoteSiteNotProvisioned() {
        webhookCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new WebhookOnlyMock(202));

        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookUrl = 'https://example.com/webhook';
        config.targetObjectApiName = 'PublicApi_Submission__c';
        config.outboundPayloadConfiguration =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';
        config.outboundRemoteSiteDomain = 'https://example.com';
        config.outboundRemoteSiteStatus = PublicApiConfigService.REMOTE_SITE_STATUS_PENDING;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'Converted'
        );

        Test.startTest();
        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config);
        Test.stopTest();

        System.assertEquals(false, outcome.deliveryResult.success);
        System.assertEquals(
            PublicApiStatusUpdateDeliveryService.ERROR_CODE_REMOTE_SITE_ERROR,
            outcome.deliveryResult.errorCode
        );
        System.assert(
            String.valueOf(outcome.deliveryResult.exceptionMessage).contains('not provisioned')
        );
        System.assertEquals(0, webhookCallCount);
    }

    @IsTest
    static void testSendStatusUpdate_ReturnsFailureWhenProvisionedDomainIsOutOfDate() {
        webhookCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new WebhookOnlyMock(202));

        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookUrl = 'https://example.com/webhook';
        config.targetObjectApiName = 'PublicApi_Submission__c';
        config.outboundPayloadConfiguration =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';
        config.outboundRemoteSiteDomain = 'https://old.example.com';
        config.outboundRemoteSiteStatus = PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'Converted'
        );

        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config);

        System.assertEquals(false, outcome.deliveryResult.success);
        System.assertEquals(
            PublicApiStatusUpdateDeliveryService.ERROR_CODE_REMOTE_SITE_ERROR,
            outcome.deliveryResult.errorCode
        );
        System.assert(
            String.valueOf(outcome.deliveryResult.exceptionMessage).contains('out of date')
        );
        System.assertEquals(0, webhookCallCount);
    }

    @IsTest
    static void testSendStatusUpdate_Maps401ToAuthHeaderErrorCode() {
        webhookCallCount = 0;
        Test.setMock(HttpCalloutMock.class, new WebhookOnlyMock(401));

        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookUrl = 'https://example.com/webhook';
        config.targetObjectApiName = 'PublicApi_Submission__c';
        config.outboundPayloadConfiguration =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';
        config.outboundRemoteSiteDomain = 'https://example.com';
        config.outboundRemoteSiteStatus = PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'Converted'
        );

        Test.startTest();
        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            PublicApiStatusUpdateDeliveryService.sendStatusUpdate(new Http(), submission, config);
        Test.stopTest();

        System.assertEquals(false, outcome.deliveryResult.success);
        System.assertEquals(
            PublicApiStatusUpdateDeliveryService.ERROR_CODE_AUTH_HEADER_ERROR,
            outcome.deliveryResult.errorCode
        );
        System.assertEquals(1, webhookCallCount);
    }
}
