@IsTest
private class PublicApiStatusUpdateTest {
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
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
                '{"inbound":[],"outbound":[{"externalKey":"email","value":"$PublicApi_Submission__c.Email__c","sortOrder":1}]}'
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
                '{"inbound":[],"outbound":[{"externalKey":"bad","value":"$Account.Name","sortOrder":1}]}'
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
            responseJson.contains('Outbound mapping configuration') ||
            responseJson.contains('does not match configured object')
        );
    }
}
