@IsTest
private class PublicApiSmokeTest {
    private class SmokeCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(202);
            res.setBody('{"accepted":true}');
            return res;
        }
    }

    @IsTest
    static void smokeInboundAndOutbound() {
        Test.setMock(HttpCalloutMock.class, new SmokeCalloutMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'smoke-key',
            Outbound_Webhook_URL__c = 'https://example.com/smoke-webhook',
            Request_Field_Mappings__c =
                '{"inbound":[{"externalKey":"email","value":"$submission.Email__c","sortOrder":1}],' +
                '"outbound":[{"externalKey":"email","value":"$submission.Email__c","sortOrder":1}]}'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"email":"smoke@example.com"}');
        req.headers.put('x-api-key', 'smoke-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        PublicApiIntakeApi.createSubmission();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Id submissionId = (Id) body.get('recordId');
        update new PublicApi_Submission__c(Id = submissionId, Status__c = 'Converted');
        Test.stopTest();

        System.assertEquals(201, res.statusCode);
        Integer deliveryCount = [
            SELECT COUNT()
            FROM PublicApi_Webhook_Delivery__c
            WHERE Intake__c = :submissionId
        ];
        System.assertEquals(1, deliveryCount);
    }
}
