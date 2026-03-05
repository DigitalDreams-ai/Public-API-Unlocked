@IsTest
private class PublicApiRemoteSiteTest {
    private static List<HttpRequest> capturedRequests = new List<HttpRequest>();

    private class MetadataApiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        MetadataApiMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            capturedRequests.add(request);
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    @IsTest
    static void testEnsureStatusWebhookRemoteSite_UsesDomainScopedName() {
        capturedRequests.clear();
        Test.setMock(HttpCalloutMock.class, new MetadataApiMock(
            200,
            metadataApiSuccess('PublicApiWebhook_Webhook')
        ));

        Test.startTest();
        String result = PublicApiRemoteSiteSettingService.ensureStatusWebhookRemoteSite(
            'https://webhook.site/4ac60226-8980-4dea-8e8f-a458f9ef9ec5'
        );
        Test.stopTest();

        System.assertEquals('PublicApiWebhook_Webhook', result);
        System.assertEquals(1, capturedRequests.size());
        HttpRequest request = capturedRequests[0];
        System.assert(request.getEndpoint().endsWith('/services/Soap/m/61.0'));
        System.assert(request.getBody().contains('<met:fullName>PublicApiWebhook_Webhook</met:fullName>'));
        System.assert(request.getBody().contains('<met:url>https://webhook.site</met:url>'));
    }

    @IsTest
    static void testCreateRemoteSiteSetting_DuplicateIsAccepted() {
        capturedRequests.clear();
        Test.setMock(HttpCalloutMock.class, new MetadataApiMock(
            200,
            metadataApiDuplicate('PublicApiWebhook_Webhook')
        ));

        Test.startTest();
        String result = PublicApiRemoteSiteSettingService.ensureStatusWebhookRemoteSite(
            'https://webhook.site/test'
        );
        Test.stopTest();

        System.assertEquals('PublicApiWebhook_Webhook', result);
    }

    @IsTest
    static void testGenerateRemoteSiteSettingName_PrefixesForPublicApi() {
        String generated = PublicApiRemoteSiteSettingService.generateRemoteSiteSettingName('https://webhook.site');
        System.assertEquals('PublicApiWebhook_Webhook', generated);
        System.assert(generated.startsWith('PublicApiWebhook_'));
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

    private static String metadataApiDuplicate(String fullName) {
        return '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
            '<soapenv:Body>' +
            '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
            '<result>' +
            '<success>false</success>' +
            '<fullName>' + fullName + '</fullName>' +
            '<errors><message>Remote Site Setting already exists</message></errors>' +
            '</result>' +
            '</createMetadataResponse>' +
            '</soapenv:Body>' +
            '</soapenv:Envelope>';
    }
}
