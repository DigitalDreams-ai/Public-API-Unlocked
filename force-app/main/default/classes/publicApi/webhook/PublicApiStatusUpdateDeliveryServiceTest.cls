@IsTest
private class PublicApiStatusUpdateDeliveryServiceTest {
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
}
