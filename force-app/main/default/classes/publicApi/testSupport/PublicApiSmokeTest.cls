@IsTest
private class PublicApiSmokeTest {
    @TestVisible
    private static List<String> capturedEndpoints = new List<String>();
    @TestVisible
    private static List<String> capturedBodies = new List<String>();
    @TestVisible
    private static List<String> capturedHeaders = new List<String>();

    private class CapturingCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            capturedEndpoints.add(req.getEndpoint());
            capturedBodies.add(req.getBody());
            Map<String, String> headerSnapshot = new Map<String, String>{
                'Content-Type' => req.getHeader('Content-Type'),
                'Authorization' => req.getHeader('Authorization'),
                'X-API-KEY' => req.getHeader('X-API-KEY'),
                'X-KEY' => req.getHeader('X-KEY'),
                'X-Signature' => req.getHeader('X-Signature'),
                'X-Custom' => req.getHeader('X-Custom'),
                'X-Trace' => req.getHeader('X-Trace'),
                'X-PublicApi-Event-Type' => req.getHeader('X-PublicApi-Event-Type')
            };
            capturedHeaders.add(JSON.serialize(headerSnapshot));

            HttpResponse res = new HttpResponse();
            if (req.getEndpoint() != null && req.getEndpoint().contains('/services/Soap/m/61.0')) {
                res.setStatusCode(200);
                res.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<soapenv:Body>' +
                    '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
                    '<result><success>true</success><fullName>PublicApiWebhook_Example</fullName></result>' +
                    '</createMetadataResponse>' +
                    '</soapenv:Body>' +
                    '</soapenv:Envelope>'
                );
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{"accepted":true}');
            return res;
        }
    }

    private static void resetCapturedCallouts() {
        capturedEndpoints.clear();
        capturedBodies.clear();
        capturedHeaders.clear();
    }

    @IsTest
    static void smokeRoutesRequestsToCorrectConfigsAndTargets() {
        PublicApi_Integration_Config__c submissionConfig = PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-route-submission',
                Target_Object_API_Name__c = 'PublicApi_Submission__c',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            )
        );

        PublicApi_Integration_Config__c taskConfig = PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-route-task',
                Target_Object_API_Name__c = 'Task',
                Inbound_Payload_Configuration__c =
                    '[' +
                        '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1},' +
                        '{"externalKey":"priority","value":"$Task.Priority","sortOrder":2}' +
                    ']',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]'
            )
        );

        Id submissionId;
        Id taskSubmissionId;
        Id taskId;
        Test.startTest();
        submissionId = createSubmission(
            'smoke-route-submission',
            new Map<String, Object>{ 'status' => 'New' }
        );
        taskSubmissionId = createSubmission(
            'smoke-route-task',
            new Map<String, Object>{ 'subject' => 'Route Me', 'priority' => 'High' }
        );
        Test.getEventBus().deliver();
        Test.stopTest();
        taskId = getTargetRecordId(taskSubmissionId);

        PublicApi_Submission__c submission = [
            SELECT Id, Status__c, PublicApi_Integration_Config__c
            FROM PublicApi_Submission__c
            WHERE Id = :submissionId
        ];
        Task createdTask = [
            SELECT Id, Subject, Priority
            FROM Task
            WHERE Id = :taskId
        ];

        System.assertEquals('New', submission.Status__c);
        System.assertEquals(submissionConfig.Id, submission.PublicApi_Integration_Config__c);
        System.assertEquals('Route Me', createdTask.Subject);
        System.assertEquals('High', createdTask.Priority);
        System.assertEquals(taskConfig.Target_Object_API_Name__c, 'Task');
    }

    @IsTest
    static void smokeIsolatesOutboundDeliveriesAcrossConfigsAndWebhooks() {
        resetCapturedCallouts();
        Test.setMock(HttpCalloutMock.class, new CapturingCalloutMock());

        PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-outbound-a',
                Outbound_Webhook_URL__c = 'https://example.com/webhook-a',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            )
        );

        PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-outbound-b',
                Outbound_Webhook_URL__c = 'https://example.com/webhook-b',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[' +
                        '{"externalKey":"state","value":"$PublicApi_Submission__c.Status__c","sortOrder":1},' +
                        '{"externalKey":"createdByApi","value":"$PublicApi_Submission__c.Created_By_PublicApi_API__c","sortOrder":2}' +
                    ']'
            )
        );

        Test.startTest();
        Id firstSubmissionId = createSubmission(
            'smoke-outbound-a',
            new Map<String, Object>{ 'status' => 'New' }
        );
        Id secondSubmissionId = createSubmission(
            'smoke-outbound-b',
            new Map<String, Object>{ 'status' => 'New' }
        );
        Test.getEventBus().deliver();
        update new List<PublicApi_Submission__c>{
            new PublicApi_Submission__c(Id = firstSubmissionId, Status__c = 'Converted'),
            new PublicApi_Submission__c(Id = secondSubmissionId, Status__c = 'Converted')
        };
        Test.getEventBus().deliver();
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Submission__c, Status__c, Request_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c IN :new Set<Id>{ firstSubmissionId, secondSubmissionId }
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, deliveries.size());
        System.assertEquals(2, capturedEndpoints.size());
        System.assert(capturedEndpoints[0].contains('webhook-a') || capturedEndpoints[1].contains('webhook-a'));
        System.assert(capturedEndpoints[0].contains('webhook-b') || capturedEndpoints[1].contains('webhook-b'));
        System.assert(
            String.valueOf(deliveries[0].Request_JSON__c).contains('"status"') ||
            String.valueOf(deliveries[1].Request_JSON__c).contains('"status"')
        );
        System.assert(
            String.valueOf(deliveries[0].Request_JSON__c).contains('"state"') ||
            String.valueOf(deliveries[1].Request_JSON__c).contains('"state"')
        );
        System.assert(
            String.valueOf(deliveries[0].Request_JSON__c).contains('"createdByApi":true') ||
            String.valueOf(deliveries[1].Request_JSON__c).contains('"createdByApi":true')
        );
    }

    @IsTest
    static void smokeResolvesExistingAndNewRelatedAccountsWithCreateMappings() {
        String lastNameField = getAccountLastNameFieldName();
        Account existing = new Account(Name = 'Existing Related Account');
        if (lastNameField != null) {
            existing.put(lastNameField, 'Existing Related Account');
        }
        existing.put('Phone', '602-555-0001');
        insert existing;

        PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-related-task',
                Target_Object_API_Name__c = 'Task',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
                Related_Record_Configuration__c =
                    '{' +
                        '"targetLookupField":"WhatId","relatedObjectApiName":"Account",' +
                        '"matchFieldName":"Name","sourceKey":"accountName",' +
                        '"createIfMissing":true,"onMultipleMatches":"UseNewest",' +
                        '"createMappings":[' +
                            '{"sourceKey":"phone","fieldName":"Phone"}' +
                        ']}'
            )
        );

        Id matchedSubmissionId;
        Id createdSubmissionId;
        Test.startTest();
        matchedSubmissionId = createSubmission(
            'smoke-related-task',
            new Map<String, Object>{
                'subject' => 'Matched Related Rule',
                'accountName' => 'Existing Related Account',
                'phone' => '602-555-9999'
            }
        );
        createdSubmissionId = createSubmission(
            'smoke-related-task',
            new Map<String, Object>{
                'subject' => 'Created Related Rule',
                'accountName' => 'Created Related Account',
                'phone' => '602-555-2222'
            }
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Id matchedTaskId = getTargetRecordId(matchedSubmissionId);
        Id createdTaskId = getTargetRecordId(createdSubmissionId);

        Task matchedTask = [SELECT WhatId FROM Task WHERE Id = :matchedTaskId];
        Task createdTask = [SELECT WhatId FROM Task WHERE Id = :createdTaskId];
        System.assertEquals(existing.Id, matchedTask.WhatId);
        System.assertNotEquals(null, createdTask.WhatId);
        System.assertNotEquals(existing.Id, createdTask.WhatId);

        Account createdAccount = [
            SELECT Id, Name, Phone
            FROM Account
            WHERE Id = :createdTask.WhatId
        ];
        System.assertEquals('Created Related Account', createdAccount.Name);
        System.assertEquals('602-555-2222', createdAccount.Phone);
    }

    @IsTest
    static void smokeGenericInboundRelatedRecordAndSubmissionOutboundWebhook() {
        resetCapturedCallouts();
        Test.setMock(HttpCalloutMock.class, new CapturingCalloutMock());

        PublicApi_Integration_Config__c config = PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-task-related-webhook',
                Target_Object_API_Name__c = 'Task',
                Outbound_Webhook_URL__c = 'https://example.com/task-webhook',
                Outbound_Trigger_Field_Name__c = 'Status__c',
                Outbound_Trigger_Field_Values__c = 'Converted',
                Inbound_Payload_Configuration__c =
                    '[' +
                        '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1},' +
                        '{"externalKey":"status","value":"$Task.Status","sortOrder":2}' +
                    ']',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$Task.Status","sortOrder":1}]',
                Related_Record_Configuration__c =
                    '{' +
                        '"targetLookupField":"WhatId","relatedObjectApiName":"Account",' +
                        '"matchFieldName":"Name","sourceKey":"accountName",' +
                        '"createIfMissing":true,"onMultipleMatches":"Error",' +
                        '"createMappings":[' +
                            '{"sourceKey":"phone","fieldName":"Phone"}' +
                        ']}'
            )
        );

        Id submissionId;
        Id taskId;
        Test.startTest();
        submissionId = createSubmission(
            'smoke-task-related-webhook',
            new Map<String, Object>{
                'subject' => 'Deferred Task',
                'status' => 'Not Started',
                'accountName' => 'Deferred Client Account',
                'phone' => '602-555-8181'
            }
        );
        Test.getEventBus().deliver();
        taskId = getTargetRecordId(submissionId);
        update new Task(Id = taskId, Status = 'Completed');
        update new PublicApi_Submission__c(Id = submissionId, Status__c = 'Converted');
        Test.getEventBus().deliver();
        Test.stopTest();

        Task taskRecord = [
            SELECT Id, WhatId, Status
            FROM Task
            WHERE Id = :taskId
        ];
        System.assertEquals('Completed', taskRecord.Status);
        System.assertNotEquals(null, taskRecord.WhatId);

        Account accountRecord = [
            SELECT Id, Name, Phone
            FROM Account
            WHERE Id = :taskRecord.WhatId
        ];
        System.assertEquals('Deferred Client Account', accountRecord.Name);
        System.assertEquals('602-555-8181', accountRecord.Phone);

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Status__c, Triggered_Status__c, Source_Object_API_Name__c, Source_Record_Id__c, Request_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submissionId
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals('Success', deliveries[0].Status__c);
        System.assertEquals('Converted', deliveries[0].Triggered_Status__c);
        System.assertEquals('PublicApi_Submission__c', deliveries[0].Source_Object_API_Name__c);
        System.assert(String.valueOf(deliveries[0].Request_JSON__c).contains('"status":"Completed"'));
    }

    @IsTest
    static void smokeSupportsDataWrapperAndFormEncodedInboundVariants() {
        PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-data-wrapper',
                Target_Object_API_Name__c = 'Task',
                Inbound_Payload_Configuration__c =
                    '[' +
                        '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1},' +
                        '{"externalKey":"priority","value":"$Task.Priority","sortOrder":2}' +
                    ']'
            )
        );

        Id wrappedSubmissionId;
        Id encodedSubmissionId;
        Test.startTest();
        wrappedSubmissionId = createSubmissionRaw(
            'smoke-data-wrapper',
            'application/json',
            '{"data":{"subject":"Wrapped Task","priority":"Normal"}}'
        );
        encodedSubmissionId = createSubmissionRaw(
            'smoke-data-wrapper',
            'application/x-www-form-urlencoded',
            'subject=Encoded+Task&priority=Low'
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        Id wrappedTaskId = getTargetRecordId(wrappedSubmissionId);
        Id encodedTaskId = getTargetRecordId(encodedSubmissionId);

        List<Task> tasks = [
            SELECT Subject, Priority
            FROM Task
            WHERE Id IN :new Set<Id>{ wrappedTaskId, encodedTaskId }
            ORDER BY Subject ASC
        ];
        System.assertEquals(2, tasks.size());
        System.assertEquals('Encoded Task', tasks[0].Subject);
        System.assertEquals('Low', tasks[0].Priority);
        System.assertEquals('Wrapped Task', tasks[1].Subject);
        System.assertEquals('Normal', tasks[1].Priority);
    }

    @IsTest
    static void smokeAppliesAuthModesAndAdditionalHeadersAcrossConfigs() {
        resetCapturedCallouts();
        Test.setMock(HttpCalloutMock.class, new CapturingCalloutMock());

        List<PublicApi_Integration_Config__c> configs = new List<PublicApi_Integration_Config__c>{
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-auth-apikey',
                Target_Object_API_Name__c = 'PublicApi_Submission__c',
                Outbound_Webhook_URL__c = 'https://example.com/auth-apikey',
                Outbound_Auth_Mode__c = 'ApiKeyHeader',
                Outbound_Header_Name__c = 'X-KEY',
                Outbound_Header_Value__c = 'key-123',
                Outbound_Additional_Headers_JSON__c = '{"X-Custom":"alpha","Content-Type":"blocked"}',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            ),
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-auth-bearer',
                Target_Object_API_Name__c = 'PublicApi_Submission__c',
                Outbound_Webhook_URL__c = 'https://example.com/auth-bearer',
                Outbound_Auth_Mode__c = 'BearerToken',
                Outbound_Header_Value__c = 'bearer-xyz',
                Outbound_Additional_Headers_JSON__c = '[{"name":"X-Trace","value":"trace-1"}]',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            ),
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-auth-basic',
                Target_Object_API_Name__c = 'PublicApi_Submission__c',
                Outbound_Webhook_URL__c = 'https://example.com/auth-basic',
                Outbound_Auth_Mode__c = 'BasicAuth',
                Outbound_Header_Value__c = 'user:pass',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            ),
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-auth-hmac',
                Target_Object_API_Name__c = 'PublicApi_Submission__c',
                Outbound_Webhook_URL__c = 'https://example.com/auth-hmac',
                Outbound_Auth_Mode__c = 'HmacSignature',
                Outbound_Header_Name__c = 'X-Signature',
                Outbound_Webhook_Secret__c = 'smoke-secret',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            )
        };
        for (PublicApi_Integration_Config__c config : configs) {
            PublicApiTestConfigFactory.insertConfig(config);
        }

        List<Id> submissionIds = new List<Id>();

        Test.startTest();
        for (PublicApi_Integration_Config__c config : configs) {
            submissionIds.add(createSubmission(config.API_Key__c, new Map<String, Object>{ 'status' => 'New' }));
        }
        Test.getEventBus().deliver();
        List<PublicApi_Submission__c> submissionUpdates = new List<PublicApi_Submission__c>();
        for (Id submissionId : submissionIds) {
            submissionUpdates.add(new PublicApi_Submission__c(Id = submissionId, Status__c = 'Converted'));
        }
        update submissionUpdates;
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(4, capturedHeaders.size());
        List<String> normalizedHeaders = new List<String>();
        for (String headerJson : capturedHeaders) {
            normalizedHeaders.add(headerJson == null ? '' : headerJson.toLowerCase());
        }
        System.assert(normalizedHeaders[0].contains('"x-key":"key-123"') || normalizedHeaders[1].contains('"x-key":"key-123"') || normalizedHeaders[2].contains('"x-key":"key-123"') || normalizedHeaders[3].contains('"x-key":"key-123"'));
        System.assert(normalizedHeaders[0].contains('"authorization":"bearer bearer-xyz"') || normalizedHeaders[1].contains('"authorization":"bearer bearer-xyz"') || normalizedHeaders[2].contains('"authorization":"bearer bearer-xyz"') || normalizedHeaders[3].contains('"authorization":"bearer bearer-xyz"'));
        System.assert(normalizedHeaders[0].contains('"authorization":"basic ') || normalizedHeaders[1].contains('"authorization":"basic ') || normalizedHeaders[2].contains('"authorization":"basic ') || normalizedHeaders[3].contains('"authorization":"basic '));
        System.assert(normalizedHeaders[0].contains('"x-signature":"') || normalizedHeaders[1].contains('"x-signature":"') || normalizedHeaders[2].contains('"x-signature":"') || normalizedHeaders[3].contains('"x-signature":"'));
        System.assert(normalizedHeaders[0].contains('"x-custom":"alpha"') || normalizedHeaders[1].contains('"x-custom":"alpha"') || normalizedHeaders[2].contains('"x-custom":"alpha"') || normalizedHeaders[3].contains('"x-custom":"alpha"'));
        System.assert(normalizedHeaders[0].contains('"x-trace":"trace-1"') || normalizedHeaders[1].contains('"x-trace":"trace-1"') || normalizedHeaders[2].contains('"x-trace":"trace-1"') || normalizedHeaders[3].contains('"x-trace":"trace-1"'));
    }

    @IsTest
    static void smokeProvisioningStateBlocksOutboundDeliveryWhenUnprovisioned() {
        resetCapturedCallouts();
        Test.setMock(HttpCalloutMock.class, new CapturingCalloutMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'smoke-provisioning',
            Endpoint_Path__c = PublicApiTestConfigFactory.getDefaultEndpointPathForApiKey('smoke-provisioning'),
            Outbound_Webhook_URL__c = 'https://example.com/provision-webhook',
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
        );
        insert config;

        Test.startTest();
        Id submissionId = createSubmission(
            'smoke-provisioning',
            new Map<String, Object>{ 'status' => 'New' }
        );
        Test.getEventBus().deliver();
        update new PublicApi_Submission__c(Id = submissionId, Status__c = 'Converted');
        Test.getEventBus().deliver();
        Test.stopTest();

        PublicApi_Webhook_Delivery__c failedDelivery = [
            SELECT Status__c, Error_Code__c, Response_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submissionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Failed', failedDelivery.Status__c);
        System.assertEquals('REMOTE_SITE_ERROR', failedDelivery.Error_Code__c);
        System.assert(String.valueOf(failedDelivery.Response_JSON__c).contains('not provisioned'));
    }

    @IsTest
    static void smokeProvisioningStateFailsWhenWebhookDomainChangesWithoutReprovision() {
        resetCapturedCallouts();
        Test.setMock(HttpCalloutMock.class, new CapturingCalloutMock());

        PublicApi_Integration_Config__c config = PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-stale-domain',
                Outbound_Webhook_URL__c = 'https://example.com/original-webhook',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            )
        );
        update new PublicApi_Integration_Config__c(
            Id = config.Id,
            Outbound_Webhook_URL__c = 'https://changed.example.org/new-webhook'
        );

        Test.startTest();
        Id submissionId = createSubmission(
            'smoke-stale-domain',
            new Map<String, Object>{ 'status' => 'New' }
        );
        Test.getEventBus().deliver();
        update new PublicApi_Submission__c(Id = submissionId, Status__c = 'Converted');
        Test.getEventBus().deliver();
        Test.stopTest();

        PublicApi_Webhook_Delivery__c failedDelivery = [
            SELECT Status__c, Error_Code__c, Response_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submissionId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Failed', failedDelivery.Status__c);
        System.assertEquals('REMOTE_SITE_ERROR', failedDelivery.Error_Code__c);
        System.assert(String.valueOf(failedDelivery.Response_JSON__c).contains('out of date'));
    }

    @IsTest
    static void smokeSubmissionOutboundSupportsMultipleConfigsForSameTargetObject() {
        resetCapturedCallouts();
        Test.setMock(HttpCalloutMock.class, new CapturingCalloutMock());

        PublicApi_Integration_Config__c configA = PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-account-outbound-a',
                Target_Object_API_Name__c = 'Task',
                Outbound_Webhook_URL__c = 'https://example.com/account-a',
                Inbound_Payload_Configuration__c =
                    '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
                Outbound_Payload_Configuration__c =
                    '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]'
            )
        );

        PublicApi_Integration_Config__c configB = PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'smoke-account-outbound-b',
                Target_Object_API_Name__c = 'Task',
                Outbound_Webhook_URL__c = 'https://example.com/account-b',
                Inbound_Payload_Configuration__c =
                    '[' +
                        '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1},' +
                        '{"externalKey":"priority","value":"$Task.Priority","sortOrder":2}' +
                    ']',
                Outbound_Payload_Configuration__c =
                    '[' +
                        '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1},' +
                        '{"externalKey":"priority","value":"$Task.Priority","sortOrder":2}' +
                    ']'
            )
        );

        Test.startTest();
        Id submissionIdA = createSubmission(
            'smoke-account-outbound-a',
            new Map<String, Object>{ 'subject' => 'Scenario Task A' }
        );
        Id submissionIdB = createSubmission(
            'smoke-account-outbound-b',
            new Map<String, Object>{ 'subject' => 'Scenario Task B', 'priority' => 'High' }
        );
        Test.getEventBus().deliver();
        update new List<PublicApi_Submission__c>{
            new PublicApi_Submission__c(Id = submissionIdA, Status__c = 'Converted'),
            new PublicApi_Submission__c(Id = submissionIdB, Status__c = 'Converted')
        };
        Test.getEventBus().deliver();
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Status__c, Source_Object_API_Name__c, Source_Record_Id__c, Submission__c, Request_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c IN :new Set<Id>{ submissionIdA, submissionIdB }
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, deliveries.size());
        System.assertEquals(2, capturedEndpoints.size());
        System.assertEquals('PublicApi_Submission__c', deliveries[0].Source_Object_API_Name__c);
        System.assertEquals('PublicApi_Submission__c', deliveries[1].Source_Object_API_Name__c);
        System.assert(
            String.valueOf(deliveries[0].Request_JSON__c).contains('"subject"') &&
            String.valueOf(deliveries[1].Request_JSON__c).contains('"subject"')
        );
        System.assert(
            String.valueOf(deliveries[0].Request_JSON__c).contains('"priority"') ||
            String.valueOf(deliveries[1].Request_JSON__c).contains('"priority"')
        );
    }

    private static Id createSubmission(String apiKey, Map<String, Object> payload) {
        return createSubmissionRaw(apiKey, 'application/json', JSON.serialize(payload));
    }

    private static Id createSubmissionRaw(String apiKey, String contentType, String rawBody) {
        RestRequest req = new RestRequest();
        req.requestURI =
            '/services/apexrest/v1/publicapi' + PublicApiTestConfigFactory.getDefaultEndpointPathForApiKey(apiKey);
        req.httpMethod = 'POST';
        if (String.isNotBlank(contentType)) {
            req.addHeader('Content-Type', contentType);
            req.headers.put('Content-Type', contentType);
        }
        req.requestBody = Blob.valueOf(rawBody);
        req.headers.put('x-api-key', apiKey);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        PublicApiSubmissionApi.createSubmission();
        System.assertEquals(201, res.statusCode, 'Body: ' + (res.responseBody == null ? '' : res.responseBody.toString()));
        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        return (Id) responseBody.get('recordId');
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
}

