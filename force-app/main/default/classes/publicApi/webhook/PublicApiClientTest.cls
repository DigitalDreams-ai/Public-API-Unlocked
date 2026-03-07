@IsTest
private class PublicApiClientTest {
    @IsTest
    static void testVerifyWebhookSignature() {
        String payload = '{"email":"test@example.com"}';
        String secret = 'topsecret';
        String signature = PublicApiClient.generateWebhookSignature(payload, secret);

        System.assertEquals(true, PublicApiClient.verifyWebhookSignature(payload, signature, secret));
        System.assertEquals(false, PublicApiClient.verifyWebhookSignature(payload, 'bad', secret));
        System.assertEquals(true, PublicApiClient.verifyWebhookSignature(payload, 'ignored', null));
        System.assertEquals(false, PublicApiClient.verifyWebhookSignature(null, signature, secret));
        System.assertEquals(null, PublicApiClient.generateWebhookSignature(null, secret));
    }
}
