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
