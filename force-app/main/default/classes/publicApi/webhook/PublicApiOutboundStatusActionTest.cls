@IsTest
private class PublicApiOutboundStatusActionTest {
    private class WebhookOnlyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setBody('{"ok":true}');
            return response;
        }
    }

    @IsTest
    static void testInvocableQueuesOutboundForNonSubmissionObject() {
        Test.setMock(HttpCalloutMock.class, new WebhookOnlyMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'account-outbound-key',
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Source_Object_API_Name__c = 'Account',
            Outbound_Payload_Configuration__c =
                '{"inbound":[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}],' +
                '"outbound":[{"externalKey":"accountName","value":"$Account.Name","sortOrder":1}]}'
        );
        insert config;

        Account accountRecord = new Account(Name = 'Acme Status Record');
        insert accountRecord;

        PublicApiOutboundStatusAction.Request request = new PublicApiOutboundStatusAction.Request();
        request.recordId = accountRecord.Id;
        request.configId = config.Id;
        request.previousStatus = 'Open';
        request.currentStatus = 'Converted';
        request.changedAt = System.now();

        Test.startTest();
        PublicApiOutboundStatusAction.enqueue(new List<PublicApiOutboundStatusAction.Request>{ request });
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Status__c,
                   Triggered_Status__c,
                   Status_Code__c,
                   Intake__c,
                   Source_Record_Id__c,
                   Source_Object_API_Name__c,
                   Request_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE PublicApi_Integration_Config__c = :config.Id
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals('Success', deliveries[0].Status__c);
        System.assertEquals('Converted', deliveries[0].Triggered_Status__c);
        System.assertEquals(200, deliveries[0].Status_Code__c);
        System.assertEquals(null, deliveries[0].Intake__c);
        System.assertEquals(accountRecord.Id, deliveries[0].Source_Record_Id__c);
        System.assertEquals('Account', deliveries[0].Source_Object_API_Name__c);
        System.assert(String.valueOf(deliveries[0].Request_JSON__c).contains('Acme Status Record'));
    }
}
