@IsTest
private class PublicApiOutboundStatusActionTest {
    private class WebhookOnlyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint() != null && request.getEndpoint().contains('/services/Soap/m/61.0')) {
                response.setStatusCode(200);
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
                    '<soapenv:Body>' +
                    '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
                    '<result><success>true</success><fullName>PublicApiWebhook_Example</fullName></result>' +
                    '</createMetadataResponse>' +
                    '</soapenv:Body>' +
                    '</soapenv:Envelope>'
                );
                return response;
            }
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
            Target_Object_API_Name__c = 'Account',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"accountName","value":"$Account.Name","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        Account accountRecord = createAccount('Acme Status Record');
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
                   Error_Code__c,
                   Submission__c,
                   Source_Record_Id__c,
                   Source_Object_API_Name__c,
                   Request_JSON__c,
                   Response_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE PublicApi_Integration_Config__c = :config.Id
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals(
            'Success',
            deliveries[0].Status__c,
            'Delivery failed. Error code: ' + deliveries[0].Error_Code__c + ' Response: ' + deliveries[0].Response_JSON__c
        );
        System.assertEquals('Converted', deliveries[0].Triggered_Status__c);
        System.assertEquals(200, deliveries[0].Status_Code__c);
        System.assertEquals(null, deliveries[0].Submission__c);
        System.assertEquals(accountRecord.Id, deliveries[0].Source_Record_Id__c);
        System.assertEquals('Account', deliveries[0].Source_Object_API_Name__c);
        System.assert(String.valueOf(deliveries[0].Request_JSON__c).contains('Acme Status Record'));
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
