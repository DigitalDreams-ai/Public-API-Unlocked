@IsTest
private class PublicApiOutboundRequestEventServiceTest {
    private class WebhookMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setBody('{"ok":true}');
            return response;
        }
    }

    @IsTest
    static void testPublishesOutboundDeliveryFromSubmissionToTargetRecord() {
        Test.setMock(HttpCalloutMock.class, new WebhookMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'outbound-event-target-backed',
            Target_Object_API_Name__c = 'Account',
            Outbound_Webhook_URL__c = 'https://example.com/outbound-event',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"accountName","value":"$Account.Name","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        Account accountRecord = createAccount('Outbound Event Account');
        insert accountRecord;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id,
            Target_Object_API_Name__c = 'Account',
            Target_Record_Id__c = accountRecord.Id
        );
        insert submission;

        Test.startTest();
        PublicApiOutboundRequestEventService.publishRequests(
            new List<PublicApiOutboundTriggerService.ChangeRequest>{
                new PublicApiOutboundTriggerService.ChangeRequest(
                    submission.Id,
                    config.Id,
                    'New',
                    'Converted',
                    System.now()
                )
            }
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        PublicApi_Webhook_Delivery__c delivery = [
            SELECT Submission__c, Source_Record_Id__c, Source_Object_API_Name__c, Triggered_Status__c, Request_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submission.Id
            LIMIT 1
        ];
        System.assertEquals(submission.Id, delivery.Submission__c);
        System.assertEquals(submission.Id, delivery.Source_Record_Id__c);
        System.assertEquals('PublicApi_Submission__c', delivery.Source_Object_API_Name__c);
        System.assertEquals('Converted', delivery.Triggered_Status__c);
        System.assert(String.valueOf(delivery.Request_JSON__c).contains('Outbound Event Account'));
    }

    @IsTest
    static void testPublishedOutboundEventUsesConfigIdCapturedAtEnqueueTime() {
        Test.setMock(HttpCalloutMock.class, new WebhookMock());

        PublicApi_Integration_Config__c originalConfig = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'outbound-event-original-config',
            Target_Object_API_Name__c = 'Account',
            Outbound_Webhook_URL__c = 'https://example.com/original-outbound-event',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"accountName","value":"$Account.Name","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(originalConfig);

        PublicApi_Integration_Config__c relinkedConfig = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'outbound-event-relinked-config',
            Target_Object_API_Name__c = 'Account',
            Outbound_Webhook_URL__c = 'https://example.com/relinked-outbound-event',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"renamed","value":"$Account.Name","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(relinkedConfig);

        Account accountRecord = createAccount('Preserve Config Identity');
        insert accountRecord;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = originalConfig.Id,
            Target_Object_API_Name__c = 'Account',
            Target_Record_Id__c = accountRecord.Id
        );
        insert submission;

        Test.startTest();
        PublicApiOutboundRequestEventService.publishRequests(
            new List<PublicApiOutboundTriggerService.ChangeRequest>{
                new PublicApiOutboundTriggerService.ChangeRequest(
                    submission.Id,
                    originalConfig.Id,
                    'New',
                    'Converted',
                    System.now()
                )
            }
        );
        update new PublicApi_Submission__c(
            Id = submission.Id,
            PublicApi_Integration_Config__c = relinkedConfig.Id
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        PublicApi_Webhook_Delivery__c delivery = [
            SELECT PublicApi_Integration_Config__c, Webhook_URL__c, Request_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submission.Id
            LIMIT 1
        ];
        System.assertEquals(originalConfig.Id, delivery.PublicApi_Integration_Config__c);
        System.assertEquals('https://example.com/original-outbound-event', delivery.Webhook_URL__c);
        System.assert(String.valueOf(delivery.Request_JSON__c).contains('"accountName"'));
    }

    @IsTest
    static void testLogsFailedDeliveryWhenTargetRecordCannotBeResolved() {
        Test.setMock(HttpCalloutMock.class, new WebhookMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'outbound-event-missing-target',
            Target_Object_API_Name__c = 'Task',
            Outbound_Webhook_URL__c = 'https://example.com/outbound-event-failure',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id,
            Target_Object_API_Name__c = 'Task'
        );
        insert submission;

        Test.startTest();
        PublicApiOutboundRequestEventService.publishRequests(
            new List<PublicApiOutboundTriggerService.ChangeRequest>{
                new PublicApiOutboundTriggerService.ChangeRequest(
                    submission.Id,
                    config.Id,
                    'New',
                    'Converted',
                    System.now()
                )
            }
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        PublicApi_Webhook_Delivery__c delivery = [
            SELECT Status__c, Error_Code__c, Response_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submission.Id
            LIMIT 1
        ];
        System.assertEquals('Failed', delivery.Status__c);
        System.assertEquals('MAPPING_ERROR', delivery.Error_Code__c);
        System.assert(String.valueOf(delivery.Response_JSON__c).contains('could not be resolved'));
    }

    @IsTest
    static void testPublishRequestsThrowsWhenEventPublishFails() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'outbound-event-publish-fail',
            Target_Object_API_Name__c = 'Task',
            Outbound_Webhook_URL__c = 'https://example.com/outbound-event-publish-fail',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id,
            Target_Object_API_Name__c = 'Task'
        );
        insert submission;

        try {
            PublicApiOutboundRequestEventService.simulatePublishFailure = true;
            PublicApiOutboundRequestEventService.publishRequests(
                new List<PublicApiOutboundTriggerService.ChangeRequest>{
                    new PublicApiOutboundTriggerService.ChangeRequest(
                        submission.Id,
                        config.Id,
                        'New',
                        'Converted',
                        System.now()
                    )
                }
            );
            System.assert(false, 'Expected outbound event publish failure.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('Failed to publish outbound delivery event'));
        } finally {
            PublicApiOutboundRequestEventService.simulatePublishFailure = false;
        }
    }

    @IsTest
    static void testToRequestItemsParsesConfigIdFromEvent() {
        Id configId = PublicApiTestConfigFactory.insertConfig(
            new PublicApi_Integration_Config__c(
                Is_Active__c = true,
                API_Key__c = 'outbound-event-parse-config-id',
                Target_Object_API_Name__c = 'Task',
                Outbound_Webhook_URL__c = 'https://example.com/outbound-event-parse-config-id'
            )
        ).Id;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = configId
        );
        insert submission;

        List<PublicApiOutboundRequestQueueable.RequestItem> items =
            PublicApiOutboundRequestEventService.toRequestItems(
                new List<PublicApi_Outbound_Request__e>{
                    new PublicApi_Outbound_Request__e(
                        Submission_Record_Id__c = String.valueOf(submission.Id),
                        Config_Id__c = String.valueOf(configId),
                        Previous_Value__c = 'Old',
                        Current_Value__c = 'New',
                        Changed_At__c = System.now()
                    )
                }
            );

        System.assertEquals(1, items.size());
        System.assertEquals(configId, items[0].configId);
    }

    private static Account createAccount(String name) {
        Account accountRecord = new Account(Name = name);
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        for (String preferredFieldName : new List<String>{ 'LastName' }) {
            if (fieldMap.containsKey(preferredFieldName) &&
                fieldMap.get(preferredFieldName).getDescribe().isCreateable()) {
                accountRecord.put(preferredFieldName, name);
                return accountRecord;
            }
        }

        for (Schema.SObjectField fieldToken : fieldMap.values()) {
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (describe.isCreateable() &&
                describe.getType() == Schema.DisplayType.String &&
                describe.getName().toLowerCase().contains('last')) {
                accountRecord.put(describe.getName(), name);
                break;
            }
        }
        return accountRecord;
    }
}
