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
                '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id
        );
        insert submission;

        Test.startTest();
        submission.Status__c = 'Converted';
        update submission;
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Id, Submission__c, Status__c, Triggered_Status__c, Status_Code__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submission.Id
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
                '[{"externalKey":"bad","value":"$Account.Name","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id
        );
        insert submission;

        Test.startTest();
        update new PublicApi_Submission__c(Id = submission.Id, Status__c = 'Referred Out');
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Status__c, Response_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submission.Id
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

    @IsTest
    static void testOutboundTriggerDisabled_DoesNotSendWebhook() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'status-test-key-trigger-disabled',
            Outbound_Trigger_Enabled__c = false,
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id
        );
        insert submission;

        Test.startTest();
        update new PublicApi_Submission__c(Id = submission.Id, Status__c = 'Converted');
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM PublicApi_Webhook_Delivery__c WHERE Submission__c = :submission.Id]
        );
    }

    @IsTest
    static void testCustomTriggerStatuses_UsesConfigValues() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        String customStatus = getCustomTriggerStatusValue();

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'status-test-key-custom-statuses',
            Outbound_Trigger_Enabled__c = true,
            Outbound_Trigger_Field_Name__c = 'Status__c',
            Outbound_Trigger_Field_Values__c = customStatus,
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id
        );
        insert submission;

        Test.startTest();
        update new PublicApi_Submission__c(Id = submission.Id, Status__c = 'Converted');
        update new PublicApi_Submission__c(Id = submission.Id, Status__c = customStatus);
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Triggered_Status__c, Status__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submission.Id
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals(customStatus, deliveries[0].Triggered_Status__c);
        System.assertEquals('Success', deliveries[0].Status__c);
    }

    @IsTest
    static void testCustomTriggerField_UsesConfiguredFieldName() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'trigger-field-api-name-key',
            Outbound_Trigger_Enabled__c = true,
            Outbound_Trigger_Field_Name__c = 'Created_By_PublicApi_API__c',
            Outbound_Trigger_Field_Values__c = 'false',
            Outbound_Webhook_URL__c = 'https://example.com/webhook',
            Outbound_Payload_Configuration__c =
                '[{"externalKey":"createdByApi","value":"$PublicApi_Submission__c.Created_By_PublicApi_API__c","sortOrder":1}]'
        );
        PublicApiTestConfigFactory.insertConfig(config);

        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'New',
            Created_By_PublicApi_API__c = true,
            PublicApi_Integration_Config__c = config.Id
        );
        insert submission;

        Test.startTest();
        update new PublicApi_Submission__c(Id = submission.Id, Created_By_PublicApi_API__c = false);
        Test.stopTest();

        List<PublicApi_Webhook_Delivery__c> deliveries = [
            SELECT Triggered_Status__c, Status__c, Request_JSON__c
            FROM PublicApi_Webhook_Delivery__c
            WHERE Submission__c = :submission.Id
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals('false', deliveries[0].Triggered_Status__c);
        System.assertEquals('Success', deliveries[0].Status__c);
        System.assert(String.valueOf(deliveries[0].Request_JSON__c).contains('"createdByApi":false'));
    }

    @IsTest
    static void testParseTriggerStatuses_SupportsCsvAndJson() {
        Set<String> csvValues = PublicApiStatusUpdateHandler.parseTriggerStatuses('Referred Out, Converted ; Signed');
        System.assertEquals(true, csvValues.contains('Referred Out'));
        System.assertEquals(true, csvValues.contains('Converted'));
        System.assertEquals(true, csvValues.contains('Signed'));

        Set<String> jsonValues = PublicApiStatusUpdateHandler.parseTriggerStatuses('["One", "Two"]');
        System.assertEquals(new Set<String>{ 'One', 'Two' }, jsonValues);
    }

    private static String getCustomTriggerStatusValue() {
        for (Schema.PicklistEntry entry : PublicApi_Submission__c.Status__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String value = entry.getValue();
            if (String.isBlank(value) || value == 'New' || value == 'Converted' || value == 'Referred Out') {
                continue;
            }
            return value;
        }
        return 'Converted';
    }
}
