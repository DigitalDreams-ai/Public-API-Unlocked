@IsTest
private class PublicApiIntakeApiTest {
    @IsTest
    static void testCreateSubmissionSuccess() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-1',
            Inbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultInboundMappingsJson(),
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson(),
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
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
            Inbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultInboundMappingsJson(),
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson(),
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
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
    static void testCreateSubmissionFormEncodedPayloadInvalidEncoding() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-4b',
            Inbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultInboundMappingsJson(),
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson(),
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.requestBody = Blob.valueOf('bad=%E0%A4%A');
        req.headers.put('x-api-key', 'api-test-key-4b');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Invalid form-encoded payload'));
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
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"name","value":"$PublicApi_Submission__c.Does_Not_Exist__c","sortOrder":1}]',
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
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

    @IsTest
    static void testCreateSubmissionRejectsOutboundOnlyMappingConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-7',
            Inbound_Payload_Configuration__c = '[]',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"status":"Converted"}');
        req.headers.put('x-api-key', 'api-test-key-7');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('At least one inbound mapping row is required'));
    }

    @IsTest
    static void testCreateSubmissionSupportsInboundTargetObjectWithoutStatusField() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-8',
            Target_Object_API_Name__c = 'Account',
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"name","value":"$Account.Name","sortOrder":1}]'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"name":"Acme Public API"}');
        req.headers.put('x-api-key', 'api-test-key-8');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Id recordId = (Id) response.get('recordId');
        Account created = [SELECT Id, Name FROM Account WHERE Id = :recordId];
        System.assertEquals('Acme Public API', created.Name);
    }

    @IsTest
    static void testCreateSubmissionResolvesRelatedAccountForContactTarget() {
        String accountLastNameFieldName = getAccountLastNameFieldName();
        String createMappingsJson =
            accountLastNameFieldName == null
                ? ''
                : ',"createMappings":[{"sourceKey":"accountLastName","fieldName":"' +
                    accountLastNameFieldName + '"}]';
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-9',
            Target_Object_API_Name__c = 'Task',
            Inbound_Payload_Configuration__c =
                '[' +
                    '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}' +
                ']',
            Related_Record_Configuration__c =
                '[' +
                    '{"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error"' +
                    createMappingsJson + '}' +
                ']'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"subject":"Resolved Task","accountName":"Resolved Account","accountLastName":"Resolved Account"}'
        );
        req.headers.put('x-api-key', 'api-test-key-9');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiIntakeApi.createSubmission();
        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Id recordId = (Id) response.get('recordId');
        Task created = [SELECT Id, Subject, WhatId FROM Task WHERE Id = :recordId];
        System.assertEquals('Resolved Task', created.Subject);
        System.assertNotEquals(null, created.WhatId);

        Account related = [SELECT Id, Name FROM Account WHERE Id = :created.WhatId];
        System.assertEquals('Resolved Account', related.Name);
    }

    private static String getAccountLastNameFieldName() {
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        for (String preferredFieldName : new List<String>{ 'LastName', 'litify_pm__Last_Name__c' }) {
            if (fieldMap.containsKey(preferredFieldName) &&
                fieldMap.get(preferredFieldName).getDescribe().isCreateable()) {
                return preferredFieldName;
            }
        }

        for (Schema.SObjectField fieldToken : fieldMap.values()) {
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (describe.isCreateable() &&
                describe.getType() == Schema.DisplayType.String &&
                describe.getName().toLowerCase().contains('last')) {
                return describe.getName();
            }
        }
        return null;
    }
}
