@IsTest
private class PublicApiIntakeApiTest {
    @IsTest
    static void testCreateSubmissionSuccess() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-1',
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultMappingsJson()
        );
        insert config;

        Map<String, Object> payload = new Map<String, Object>{
            'source' => 'test-suite',
            'reference' => 'submission-001'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', 'api-test-key-1');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        PublicApiIntakeApi.createSubmission();
        Test.stopTest();

        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertNotEquals(null, response.get('recordId'));

        Id recordId = (Id) response.get('recordId');
        PublicApi_Submission__c created = [
            SELECT Created_By_PublicApi_API__c,
                   PublicApi_Integration_Config__c,
                   Received_At__c,
                   Raw_Payload__c,
                   Status__c
            FROM PublicApi_Submission__c
            WHERE Id = :recordId
        ];
        System.assertEquals(true, created.Created_By_PublicApi_API__c);
        System.assertEquals(config.Id, created.PublicApi_Integration_Config__c);
        System.assertNotEquals(null, created.Received_At__c);
        System.assert(String.isNotBlank(created.Raw_Payload__c));
        System.assertEquals('New', created.Status__c);
    }

    @IsTest
    static void testCreateSubmissionMissingApiKey() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"first_name":"NoKey"}');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(401, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionInvalidJson() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-2'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{ invalid }');
        req.headers.put('x-api-key', 'api-test-key-2');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(400, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionInvalidSignature() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-3',
            Webhook_Secret__c = 'expected-secret'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"first_name":"Signed"}');
        req.headers.put('x-api-key', 'api-test-key-3');
        req.headers.put('x-publicapi-signature', 'bad-signature');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(401, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionFormEncodedPayload() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-4',
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultMappingsJson()
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.requestBody = Blob.valueOf('first_name=Form&last_name=Encoded&email=form%40example.com');
        req.headers.put('x-api-key', 'api-test-key-4');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(201, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionRejectsMissingInboundMappingConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-5'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"first_name":"NoMap"}');
        req.headers.put('x-api-key', 'api-test-key-5');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Inbound mapping configuration is required'));
    }

    @IsTest
    static void testCreateSubmissionRejectsInvalidInboundMappingConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-6',
            Outbound_Payload_Configuration__c =
                '{"inbound":[{"externalKey":"name","value":"$PublicApi_Submission__c.Does_Not_Exist__c","sortOrder":1}],"outbound":[]}'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"name":"Bad Field"}');
        req.headers.put('x-api-key', 'api-test-key-6');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Inbound mapping configuration is invalid'));
    }
}
