@IsTest
private class PublicApiStatusUpdateQueueableTest {
    private static Integer metadataCallCount = 0;
    private static Integer webhookCallCount = 0;

    private class MetadataAndWebhookMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint() != null && request.getEndpoint().contains('/services/Soap/m/61.0')) {
                metadataCallCount++;
                response.setStatusCode(200);
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<soapenv:Body>' +
                    '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
                    '<result><success>true</success><fullName>PublicApiWebhook_Example</fullName></result>' +
                    '</createMetadataResponse>' +
                    '</soapenv:Body>' +
                    '</soapenv:Envelope>'
                );
                return response;
            }

            webhookCallCount++;
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setBody('{"ok":true}');
            return response;
        }
    }

    @IsTest
    static void testApplyAuthHeadersAllModes() {
        HttpRequest request = new HttpRequest();
        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'ApiKeyHeader';
        config.outboundHeaderName = 'X-KEY';
        config.outboundHeaderValue = 'value-1';
        PublicApiStatusUpdateDeliveryService.applyAuthHeaders(request, config, '{"x":1}');
        System.assertEquals('value-1', request.getHeader('X-KEY'));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'BearerToken';
        config.outboundHeaderValue = 'bearer-token';
        PublicApiStatusUpdateDeliveryService.applyAuthHeaders(request, config, '{"x":1}');
        System.assertEquals('Bearer bearer-token', request.getHeader('Authorization'));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'BasicAuth';
        config.outboundHeaderValue = 'user:pass';
        PublicApiStatusUpdateDeliveryService.applyAuthHeaders(request, config, '{"x":1}');
        System.assert(request.getHeader('Authorization').startsWith('Basic '));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'HmacSignature';
        config.outboundHeaderName = 'X-Signature';
        config.statusUpdateWebhookSecret = 'secret-1';
        PublicApiStatusUpdateDeliveryService.applyAuthHeaders(request, config, '{"x":1}');
        System.assertNotEquals(null, request.getHeader('X-Signature'));

        try {
            request = new HttpRequest();
            config = new PublicApiConfigService.Config();
            config.outboundAuthMode = 'ApiKeyHeader';
            PublicApiStatusUpdateDeliveryService.applyAuthHeaders(request, config, '{"x":1}');
            System.assert(false, 'Expected invalid auth configuration to throw.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('Outbound auth configuration is invalid'));
        }
    }

    @IsTest
    static void testApplyAdditionalHeadersMapAndList() {
        HttpRequest request = new HttpRequest();
        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.outboundAdditionalHeadersJson = '{"X-Custom":"A","Content-Type":"blocked"}';
        PublicApiStatusUpdateDeliveryService.applyAdditionalHeaders(request, config);
        System.assertEquals('A', request.getHeader('X-Custom'));
        System.assertEquals(null, request.getHeader('Content-Type'));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAdditionalHeadersJson = '[{"name":"X-First","value":"1"},{"header":"X-Second","value":"2"}]';
        PublicApiStatusUpdateDeliveryService.applyAdditionalHeaders(request, config);
        System.assertEquals('1', request.getHeader('X-First'));
        System.assertEquals('2', request.getHeader('X-Second'));

        try {
            request = new HttpRequest();
            config = new PublicApiConfigService.Config();
            config.outboundAdditionalHeadersJson = '{ bad json }';
            PublicApiStatusUpdateDeliveryService.applyAdditionalHeaders(request, config);
            System.assert(false, 'Expected invalid additional headers JSON to throw.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('Outbound header configuration is invalid'));
        }
    }

    @IsTest
    static void testBatchAndDeserializeHelpers() {
        List<String> source = new List<String>();
        Integer total = PublicApiStatusUpdateQueueable.MAX_DELIVERIES_PER_JOB + 2;
        for (Integer i = 0; i < total; i++) {
            source.add('item-' + String.valueOf(i));
        }

        List<String> batch = PublicApiStatusUpdateQueueable.takeBatch(source);
        List<String> remaining = PublicApiStatusUpdateQueueable.dropBatch(source);
        System.assertEquals(PublicApiStatusUpdateQueueable.MAX_DELIVERIES_PER_JOB, batch.size());
        System.assertEquals(2, remaining.size());

        List<String> serialized = new List<String>{
            JSON.serialize(new PublicApiStatusUpdateQueueable.DeliveryItem(
                Id.valueOf('001000000000001AAA'),
                Id.valueOf('001000000000002AAA'),
                'New',
                'Converted',
                System.now()
            )),
            'not-json'
        };
        List<PublicApiStatusUpdateQueueable.DeliveryItem> items =
            PublicApiStatusUpdateQueueable.deserializeItems(serialized);
        System.assertEquals(1, items.size());
    }

    @IsTest
    static void testQueueable_NoSessionId_SkipsProvisioningAndStillSendsWebhook() {
        metadataCallCount = 0;
        webhookCallCount = 0;
        PublicApiStatusUpdateDeliveryService.provisionedWebhookDomainsInTransaction.clear();
        Test.setMock(HttpCalloutMock.class, new MetadataAndWebhookMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'queueable-no-session-key',
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Payload_Configuration__c =
                '{"inbound":[],"outbound":[{"externalKey":"email","value":"$intakes.Email__c","sortOrder":1}]}'
        );
        insert config;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            First_Name__c = 'Queue',
            Last_Name__c = 'NoSession',
            Email__c = 'queueable-nosession@example.com',
            Status__c = 'Converted',
            Created_By_PublicApi_API__c = true
        );
        insert submission;

        PublicApiStatusUpdateQueueable.DeliveryItem item = new PublicApiStatusUpdateQueueable.DeliveryItem(
            submission.Id,
            config.Id,
            'Referred Out',
            'Converted',
            System.now(),
            null
        );

        Test.startTest();
        PublicApiStatusUpdateQueueable.enqueue(
            new List<PublicApiStatusUpdateQueueable.DeliveryItem>{ item }
        );
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Status__c, Status_Code__c, Error_Code__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Intake__c = :submission.Id
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals('Success', deliveries[0].Status__c);
        System.assertEquals(200, deliveries[0].Status_Code__c);
        System.assertEquals(null, deliveries[0].Error_Code__c);
        System.assertEquals(0, metadataCallCount, 'Remote-site provisioning should be skipped without a session ID.');
        System.assertEquals(1, webhookCallCount, 'Webhook callout should still occur.');
    }
}
