@IsTest
private class PublicApiSubmissionApiTest {
    @IsTest
    static void testCreateSubmissionSuccess() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-1',
            Endpoint_Path__c = '/submission-success',
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
        req.requestURI = '/services/apexrest/v1/publicapi/submission-success';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.headers.put('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', 'api-test-key-1');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        PublicApiSubmissionApi.createSubmission();
        Test.getEventBus().deliver();
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
                   Request_Content_Type__c,
                   Target_Object_API_Name__c,
                   Target_Record_Id__c,
                   Processing_Status__c,
                   Related_Record_Status__c,
                   Effective_Config_JSON__c
            FROM PublicApi_Submission__c
            WHERE Id = :recordId
        ];
        System.assertEquals(true, created.Created_By_PublicApi_API__c);
        System.assertEquals(config.Id, created.PublicApi_Integration_Config__c);
        System.assertNotEquals(null, created.Received_At__c);
        System.assert(String.isNotBlank(created.Raw_Payload__c));
        System.assertEquals('application/json', created.Request_Content_Type__c);
        System.assertEquals('PublicApi_Submission__c', created.Target_Object_API_Name__c);
        System.assertEquals(String.valueOf(recordId), created.Target_Record_Id__c);
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED, created.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.RELATED_STATUS_NOT_CONFIGURED, created.Related_Record_Status__c);
        System.assert(String.isNotBlank(created.Effective_Config_JSON__c));
    }

    @IsTest
    static void testCreateSubmissionMissingApiKey() {
        insert new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'missing-key-test',
            Endpoint_Path__c = '/submissions',
            Inbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultInboundMappingsJson(),
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson(),
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
        );

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"first_name":"NoKey"}');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(401, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionInvalidJson() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-2',
            Endpoint_Path__c = '/submissions'
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

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(400, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionInvalidSignature() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-3',
            Endpoint_Path__c = '/submissions',
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

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(401, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionFormEncodedPayload() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-4',
            Endpoint_Path__c = '/submissions',
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

        Test.startTest();
        PublicApiSubmissionApi.createSubmission();
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(201, res.statusCode);
    }

    @IsTest
    static void testCreateSubmissionFormEncodedPayloadInvalidEncoding() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-4b',
            Endpoint_Path__c = '/submissions',
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

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Invalid form-encoded payload'));
        PublicApi_Submission__c auditRecord = [
            SELECT Processing_Status__c, Processing_Error_Category__c, Raw_Payload__c
            FROM PublicApi_Submission__c
            WHERE PublicApi_Integration_Config__c = :config.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_FAILED, auditRecord.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.ERROR_CATEGORY_PAYLOAD, auditRecord.Processing_Error_Category__c);
        System.assert(auditRecord.Raw_Payload__c.contains('bad=%E0%A4%A'));
    }

    @IsTest
    static void testCreateSubmissionRejectsOversizedPayloadBeforeAsyncProcessing() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-oversized',
            Endpoint_Path__c = '/oversized',
            Inbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultInboundMappingsJson(),
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson(),
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
        );
        insert config;

        String oversizedValue = repeatCharacter('x', PublicApiSubmissionService.RAW_PAYLOAD_MAX_LENGTH);
        String oversizedRequestBody = '{"source":"' + oversizedValue + '"}';

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/oversized';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(oversizedRequestBody);
        req.headers.put('x-api-key', 'api-test-key-oversized');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(413, res.statusCode);
        System.assert(res.responseBody.toString().contains('Request body exceeds maximum supported size'));

        PublicApi_Submission__c auditRecord = [
            SELECT Processing_Status__c, Processing_Error_Category__c, Processing_Error_Message__c, Raw_Payload__c
            FROM PublicApi_Submission__c
            WHERE PublicApi_Integration_Config__c = :config.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_FAILED, auditRecord.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.ERROR_CATEGORY_PAYLOAD, auditRecord.Processing_Error_Category__c);
        System.assert(auditRecord.Processing_Error_Message__c.contains('Request body exceeds maximum supported size'));
        System.assertEquals(PublicApiSubmissionService.RAW_PAYLOAD_MAX_LENGTH, auditRecord.Raw_Payload__c.length());
    }

    @IsTest
    static void testCreateSubmissionReturns503WhenSubmissionRequestEventPublishFails() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-publish-fail',
            Endpoint_Path__c = '/publish-fail',
            Inbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultInboundMappingsJson(),
            Outbound_Payload_Configuration__c = PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson(),
            Target_Object_API_Name__c = 'PublicApi_Submission__c'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/publish-fail';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf('{"source":"publish failure"}');
        req.headers.put('x-api-key', 'api-test-key-publish-fail');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        try {
            PublicApiSubmissionRequestEventService.simulatePublishFailure = true;
            PublicApiSubmissionApi.createSubmission();
        } finally {
            PublicApiSubmissionRequestEventService.simulatePublishFailure = false;
        }

        System.assertEquals(503, res.statusCode);
        System.assert(res.responseBody.toString().contains('Failed to publish submission processing event'));

        PublicApi_Submission__c auditRecord = [
            SELECT Processing_Status__c,
                   Processing_Error_Category__c,
                   Processing_Error_Message__c,
                   Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE PublicApi_Integration_Config__c = :config.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_FAILED, auditRecord.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.ERROR_CATEGORY_EVENT_PUBLISH, auditRecord.Processing_Error_Category__c);
        System.assert(auditRecord.Processing_Error_Message__c.contains('Failed to publish submission processing event'));
        System.assertEquals(null, auditRecord.Target_Record_Id__c);
    }

    @IsTest
    static void testCreateSubmissionRejectsMissingInboundMappingConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-5',
            Endpoint_Path__c = '/submissions'
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

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Inbound mapping configuration is required'));
    }

    @IsTest
    static void testCreateSubmissionRejectsInvalidInboundMappingConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-6',
            Endpoint_Path__c = '/submissions',
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

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Inbound mapping configuration is invalid'));
    }

    @IsTest
    static void testCreateSubmissionRejectsOutboundOnlyMappingConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-7',
            Endpoint_Path__c = '/submissions',
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

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('At least one inbound mapping row is required'));
    }

    @IsTest
    static void testCreateSubmissionRejectsInvalidRelatedRecordConfigurationImmediately() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-7b',
            Endpoint_Path__c = '/submissions',
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
            Target_Object_API_Name__c = 'Task',
            Related_Record_Configuration__c =
                '{' +
                    '"targetLookupField":"NotARealLookup__c","relatedObjectApiName":"Account",' +
                    '"matchFieldName":"Name","sourceKey":"accountName","createIfMissing":false' +
                '}'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"subject":"Invalid Related Rule","accountName":"Acme"}');
        req.headers.put('x-api-key', 'api-test-key-7b');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Related record configuration is invalid'));
        System.assertEquals(0, [SELECT Count() FROM Task WHERE Subject = 'Invalid Related Rule']);
        PublicApi_Submission__c auditRecord = [
            SELECT Processing_Status__c, Processing_Error_Category__c, Processing_Error_Message__c, Raw_Payload__c
            FROM PublicApi_Submission__c
            WHERE PublicApi_Integration_Config__c = :config.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_FAILED, auditRecord.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.ERROR_CATEGORY_CONFIGURATION, auditRecord.Processing_Error_Category__c);
        System.assert(String.isNotBlank(auditRecord.Processing_Error_Message__c));
        System.assert(auditRecord.Raw_Payload__c.contains('Invalid Related Rule'));
    }

    @IsTest
    static void testCreateSubmissionRejectsLegacyArrayRelatedRecordConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-7c',
            Endpoint_Path__c = '/submissions',
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
            Target_Object_API_Name__c = 'Task',
            Related_Record_Configuration__c =
                '[' +
                    '{"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error"}' +
                ']'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"subject":"Legacy Array Related Rule","accountName":"Legacy Array Account"}');
        req.headers.put('x-api-key', 'api-test-key-7c');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Related record configuration must be a JSON object'));
        System.assertEquals(0, [SELECT Count() FROM Task WHERE Subject = 'Legacy Array Related Rule']);
        PublicApi_Submission__c auditRecord = [
            SELECT Processing_Status__c, Processing_Error_Category__c, Processing_Error_Message__c, Raw_Payload__c
            FROM PublicApi_Submission__c
            WHERE PublicApi_Integration_Config__c = :config.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_FAILED, auditRecord.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.ERROR_CATEGORY_CONFIGURATION, auditRecord.Processing_Error_Category__c);
        System.assert(String.isNotBlank(auditRecord.Processing_Error_Message__c));
        System.assert(auditRecord.Raw_Payload__c.contains('Legacy Array Related Rule'));
    }

    @IsTest
    static void testCreateSubmissionSupportsInboundTargetObjectWithoutStatusField() {
        String configuredRecordTypeDeveloperName = getConfiguredAccountRecordTypeDeveloperName();
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-8',
            Endpoint_Path__c = '/submissions',
            Target_Object_API_Name__c = 'Account',
            Target_Record_Type_Developer_Name__c = configuredRecordTypeDeveloperName,
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

        Test.startTest();
        PublicApiSubmissionApi.createSubmission();
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Id submissionId = (Id) response.get('recordId');
        Id recordId = getTargetRecordId(submissionId);
        SObject created = queryAccount(recordId, null);
        System.assertEquals('Acme Public API', created.get('Name'));
        if (!String.isBlank(configuredRecordTypeDeveloperName)) {
            Id expectedRecordTypeId =
                PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, configuredRecordTypeDeveloperName);
            if (expectedRecordTypeId != null && accountSupportsRecordTypes()) {
                System.assertEquals(expectedRecordTypeId, created.get('RecordTypeId'));
            }
        }
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
            Endpoint_Path__c = '/submissions',
            Target_Object_API_Name__c = 'Task',
            Inbound_Payload_Configuration__c =
                '[' +
                    '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}' +
                ']',
            Related_Record_Configuration__c =
                '{' +
                    '"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error"' +
                    createMappingsJson + '}'
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

        Test.startTest();
        PublicApiSubmissionApi.createSubmission();
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Id submissionId = (Id) response.get('recordId');
        Id recordId = getTargetRecordId(submissionId);
        Task created = [SELECT Id, Subject, WhatId FROM Task WHERE Id = :recordId];
        System.assertEquals('Resolved Task', created.Subject);
        System.assertNotEquals(null, created.WhatId);

        SObject related = queryAccount(created.WhatId, null);
        System.assertEquals('Resolved Account', related.get('Name'));
    }

    @IsTest
    static void testCreateSubmissionCreatesRelatedAccountWhenNameMustBeDerived() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'api-test-key-10',
            Endpoint_Path__c = '/submissions',
            Target_Object_API_Name__c = 'Task',
            Inbound_Payload_Configuration__c =
                '[' +
                    '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}' +
                ']',
            Related_Record_Configuration__c =
                '{' +
                    '"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"email","createIfMissing":true,"onMultipleMatches":"Error"' +
                '}'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"subject":"Derived Account Task","firstName":"Jamie","lastName":"Fox","email":"jamie.fox@example.com"}'
        );
        req.headers.put('x-api-key', 'api-test-key-10');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        PublicApiSubmissionApi.createSubmission();
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Id submissionId = (Id) response.get('recordId');
        Id recordId = getTargetRecordId(submissionId);
        Task created = [SELECT Id, Subject, WhatId FROM Task WHERE Id = :recordId];
        System.assertNotEquals(null, created.WhatId);

        String accountLastNameFieldName = getAccountLastNameFieldName();
        SObject related = queryAccount(created.WhatId, accountLastNameFieldName);
        System.assert(String.isNotBlank(String.valueOf(related.get('Name'))));
        if (accountLastNameFieldName != null) {
            System.assertEquals('Fox', related.get(accountLastNameFieldName));
        }
    }

    @IsTest
    static void testCreateSubmissionRoutesByEndpointPath() {
        insert new List<PublicApi_Integration_Config__c>{
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'shared-api-key',
                Endpoint_Path__c = '/alpha',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
                Target_Object_API_Name__c = 'Task'
            ),
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'shared-api-key',
                Endpoint_Path__c = '/beta',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
                Target_Object_API_Name__c = 'Task'
            )
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/beta';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"subject":"Path Routed Task"}');
        req.headers.put('x-api-key', 'shared-api-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        PublicApiSubmissionApi.createSubmission();
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(201, res.statusCode);
        Id submissionId = (Id) ((Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString())).get('recordId');
        PublicApi_Submission__c created = [
            SELECT PublicApi_Integration_Config__r.Endpoint_Path__c
            FROM PublicApi_Submission__c
            WHERE Id = :submissionId
        ];
        System.assertEquals('/beta', created.PublicApi_Integration_Config__r.Endpoint_Path__c);
    }

    @IsTest
    static void testCreateSubmissionSupportsLegacyBlankEndpointPathAtDefaultRoute() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'legacy-default-endpoint-key',
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
            Target_Object_API_Name__c = 'Task'
        );
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/submissions';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"subject":"Legacy Default Route"}');
        req.headers.put('x-api-key', 'legacy-default-endpoint-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        PublicApiSubmissionApi.createSubmission();
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));
        Id submissionId = (Id) ((Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString())).get('recordId');
        PublicApi_Submission__c created = [
            SELECT PublicApi_Integration_Config__c
            FROM PublicApi_Submission__c
            WHERE Id = :submissionId
        ];
        System.assertEquals(config.Id, created.PublicApi_Integration_Config__c);
    }

    @IsTest
    static void testCreateSubmissionReturnsNotFoundForUnknownEndpoint() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/publicapi/does-not-exist';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"subject":"No Match"}');
        req.headers.put('x-api-key', 'unknown-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(404, res.statusCode);
    }

    private static String getAccountLastNameFieldName() {
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        for (String preferredFieldName : new List<String>{ 'LastName' }) {
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

    private static String getConfiguredAccountRecordTypeDeveloperName() {
        if (!accountSupportsRecordTypes()) {
            return null;
        }
        Id businessRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        if (businessRecordTypeId != null) {
            return 'Business';
        }
        return null;
    }

    private static Id getTargetRecordId(Id submissionId) {
        PublicApi_Submission__c submissionRecord = [
            SELECT Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE Id = :submissionId
        ];
        return submissionRecord.Target_Record_Id__c == null
            ? null
            : (Id) submissionRecord.Target_Record_Id__c;
    }

    private static SObject queryAccount(Id accountId, String accountLastNameFieldName) {
        List<String> fieldNames = new List<String>{ 'Id', 'Name' };
        if (accountSupportsRecordTypes()) {
            fieldNames.add('RecordTypeId');
        }
        if (String.isNotBlank(accountLastNameFieldName)) {
            fieldNames.add(accountLastNameFieldName);
        }
        return Database.query(
            'SELECT ' + String.join(fieldNames, ', ') + ' FROM Account WHERE Id = :accountId'
        );
    }

    private static Boolean accountSupportsRecordTypes() {
        return Account.SObjectType.getDescribe().fields.getMap().containsKey('RecordTypeId');
    }

    private static String repeatCharacter(String characterValue, Integer count) {
        return ''.leftPad(count, characterValue);
    }

}

