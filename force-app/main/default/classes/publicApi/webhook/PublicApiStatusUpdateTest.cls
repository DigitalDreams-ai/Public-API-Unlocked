@IsTest
private class PublicApiStatusUpdateTest {
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    @IsTest
    static void testStatusChangeQueuesAndSendsWebhook() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'status-test-key-1',
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Payload_Configuration__c =
                '{"inbound":[],"outbound":[{"externalKey":"email","value":"$intakes.Email__c","sortOrder":1}]}'
        );
        insert config;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            First_Name__c = 'Jane',
            Last_Name__c = 'Smith',
            Email__c = 'jane@example.com',
            Status__c = 'New',
            Created_By_PublicApi_API__c = true
        );
        insert submission;
        PublicApiIntakeTrackingService.trackIntake(submission.Id, config.Id);

        Test.startTest();
        submission.Status__c = 'Converted';
        update submission;
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Id, Intake__c, Status__c, Triggered_Status__c, Status_Code__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Intake__c = :submission.Id
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals('Success', deliveries[0].Status__c);
        System.assertEquals('Converted', deliveries[0].Triggered_Status__c);
        System.assertEquals(200, deliveries[0].Status_Code__c);
    }

    @IsTest
    static void testInvalidOutboundFieldMappingLogsFailedDelivery() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'status-test-key-2',
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Payload_Configuration__c =
                '{"inbound":[],"outbound":[{"externalKey":"bad","value":"$submission.Email__c","sortOrder":1}]}'
        );
        insert config;

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            First_Name__c = 'Bad',
            Last_Name__c = 'Field',
            Email__c = 'bad@example.com',
            Status__c = 'New',
            Created_By_PublicApi_API__c = true
        );
        insert submission;
        PublicApiIntakeTrackingService.trackIntake(submission.Id, config.Id);

        Test.startTest();
        update new PublicApi_Submission__c(Id = submission.Id, Status__c = 'Referred Out');
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Status__c, Response_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Intake__c = :submission.Id
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals('Failed', deliveries[0].Status__c);
        String responseJson = String.valueOf(deliveries[0].Response_JSON__c);
        System.assert(String.isNotBlank(responseJson));
        System.assert(
            responseJson.contains('Invalid field reference') ||
            responseJson.contains('Outbound mapping configuration')
        );
    }
}
