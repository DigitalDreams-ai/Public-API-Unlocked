@IsTest
private class PublicApiStatusUpdateQueueableTest {
    @IsTest
    static void testApplyAuthHeadersAllModes() {
        HttpRequest request = new HttpRequest();
        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'ApiKeyHeader';
        config.outboundHeaderName = 'X-KEY';
        config.outboundHeaderValue = 'value-1';
        PublicApiStatusUpdateQueueable.applyAuthHeaders(request, config, '{"x":1}');
        System.assertEquals('value-1', request.getHeader('X-KEY'));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'BearerToken';
        config.outboundHeaderValue = 'bearer-token';
        PublicApiStatusUpdateQueueable.applyAuthHeaders(request, config, '{"x":1}');
        System.assertEquals('Bearer bearer-token', request.getHeader('Authorization'));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'BasicAuth';
        config.outboundHeaderValue = 'user:pass';
        PublicApiStatusUpdateQueueable.applyAuthHeaders(request, config, '{"x":1}');
        System.assert(request.getHeader('Authorization').startsWith('Basic '));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAuthMode = 'HmacSignature';
        config.outboundHeaderName = 'X-Signature';
        config.statusUpdateWebhookSecret = 'secret-1';
        PublicApiStatusUpdateQueueable.applyAuthHeaders(request, config, '{"x":1}');
        System.assertNotEquals(null, request.getHeader('X-Signature'));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.statusUpdateWebhookSecret = 'blank-auth-secret';
        PublicApiStatusUpdateQueueable.applyAuthHeaders(request, config, '{"x":1}');
        System.assertEquals(null, request.getHeader(PublicApiStatusUpdateQueueable.DEFAULT_SIGNATURE_HEADER));
    }

    @IsTest
    static void testApplyAdditionalHeadersMapAndList() {
        HttpRequest request = new HttpRequest();
        PublicApiConfigService.Config config = new PublicApiConfigService.Config();
        config.outboundAdditionalHeadersJson = '{"X-Custom":"A","Content-Type":"blocked"}';
        PublicApiStatusUpdateQueueable.applyAdditionalHeaders(request, config);
        System.assertEquals('A', request.getHeader('X-Custom'));
        System.assertEquals(null, request.getHeader('Content-Type'));

        request = new HttpRequest();
        config = new PublicApiConfigService.Config();
        config.outboundAdditionalHeadersJson = '[{"name":"X-First","value":"1"},{"header":"X-Second","value":"2"}]';
        PublicApiStatusUpdateQueueable.applyAdditionalHeaders(request, config);
        System.assertEquals('1', request.getHeader('X-First'));
        System.assertEquals('2', request.getHeader('X-Second'));
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
}
