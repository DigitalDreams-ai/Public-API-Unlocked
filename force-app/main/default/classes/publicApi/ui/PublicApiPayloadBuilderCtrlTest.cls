@IsTest
private class PublicApiPayloadBuilderCtrlTest {
    private class MetadataApiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        MetadataApiMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    @IsTest
    static void testPayloadSettingsRoundTrip() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'payload-builder-test-key'
        );
        insert config;

        String triggerFieldName = selectPreferredTriggerFieldName('PublicApi_Submission__c');
        String triggerFieldValues = selectValidTriggerValues('PublicApi_Submission__c', triggerFieldName);

        PublicApiPayloadBuilderCtrl.PayloadSettings initialSettings =
            PublicApiPayloadBuilderCtrl.getPayloadSettings(config.Id);
        System.assertNotEquals(null, initialSettings);
        System.assertNotEquals(null, initialSettings.defaultInboundJson);
        System.assertNotEquals(null, initialSettings.defaultOutboundJson);

        String inboundJson =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';
        String outboundJson =
            '[{"externalKey":"createdDate","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":1}]';
        String relatedRecordJson =
            '[' +
                '{"targetLookupField":"PublicApi_Integration_Config__c","relatedObjectApiName":"PublicApi_Integration_Config__c",' +
                '"matchFieldName":"API_Key__c","sourceKey":"configKey","createIfMissing":true,"onMultipleMatches":"Error",' +
                '"createMappings":[{"sourceKey":"configKey","fieldName":"API_Key__c"}]}' +
            ']';

        PublicApiPayloadBuilderCtrl.savePayloadSettings(
            config.Id,
            false,
            'PublicApi_Submission__c',
            relatedRecordJson,
            true,
            triggerFieldName,
            triggerFieldValues,
            inboundJson,
            outboundJson
        );

        PublicApi_Integration_Config__c updated = [
            SELECT Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :config.Id
        ];
        System.assertEquals(inboundJson, updated.Inbound_Payload_Configuration__c);
        System.assertEquals(outboundJson, updated.Outbound_Payload_Configuration__c);
        System.assertEquals(true, updated.Outbound_Trigger_Enabled__c);
        System.assertEquals(triggerFieldName, updated.Outbound_Trigger_Field_Name__c);
        System.assertEquals(triggerFieldValues, updated.Outbound_Trigger_Field_Values__c);
        System.assertEquals(relatedRecordJson, updated.Related_Record_Configuration__c);
        System.assertEquals('PublicApi_Submission__c', updated.Target_Object_API_Name__c);
        System.assertEquals(false, updated.Sync_Inbound_And_Outbound__c);
    }

    @IsTest
    static void testGetTriggerMetadata() {
        List<String> fieldNames = PublicApiPayloadBuilderCtrl.getTriggerFieldNames('PublicApi_Submission__c');
        System.assertEquals(true, fieldNames.size() > 0);
        System.assertEquals(true, fieldNames.contains(selectPreferredTriggerFieldName('PublicApi_Submission__c')));

        List<String> fieldValues = PublicApiPayloadBuilderCtrl.getTriggerFieldValues(
            'PublicApi_Submission__c',
            selectBooleanCapableTriggerFieldName('PublicApi_Submission__c')
        );
        System.assertEquals(new List<String>{ 'true', 'false' }, fieldValues);

        List<String> lookupFields = PublicApiPayloadBuilderCtrl.getLookupFieldNames('PublicApi_Submission__c');
        System.assertEquals(true, lookupFields.contains('PublicApi_Integration_Config__c'));

        List<String> lookupTargetObjects = PublicApiPayloadBuilderCtrl.getLookupTargetObjectApiNames(
            'PublicApi_Submission__c',
            'PublicApi_Integration_Config__c'
        );
        System.assertEquals(new List<String>{ 'PublicApi_Integration_Config__c' }, lookupTargetObjects);
    }

    private static String selectPreferredTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadBuilderCtrl.getTriggerFieldNames(objectApiName);
        System.assertEquals(true, fieldNames.size() > 0, 'Expected at least one trigger field.');
        if (fieldNames.contains('Created_By_PublicApi_API__c')) {
            return 'Created_By_PublicApi_API__c';
        }
        if (fieldNames.contains('Status__c')) {
            return 'Status__c';
        }
        return fieldNames[0];
    }

    private static String selectBooleanCapableTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadBuilderCtrl.getTriggerFieldNames(objectApiName);
        for (String fieldName : fieldNames) {
            List<String> values =
                PublicApiPayloadBuilderCtrl.getTriggerFieldValues(objectApiName, fieldName);
            if (values.size() == 2 && values[0] == 'true' && values[1] == 'false') {
                return fieldName;
            }
        }
        System.assert(false, 'Expected at least one boolean-style trigger field.');
        return null;
    }

    private static String selectValidTriggerValues(String objectApiName, String fieldName) {
        List<String> suggestedValues =
            PublicApiPayloadBuilderCtrl.getTriggerFieldValues(objectApiName, fieldName);
        if (suggestedValues.isEmpty()) {
            return null;
        }
        return suggestedValues[0];
    }

    @IsTest
    static void testHeaderSettingsRoundTrip() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'header-builder-test-key'
        );
        insert config;

        PublicApiPayloadBuilderCtrl.saveHeaderSettings(
            config.Id,
            'ApiKeyHeader',
            'application/json',
            'X-API-KEY',
            'abc123',
            '{"X-Custom":"value"}'
        );

        PublicApiPayloadBuilderCtrl.HeaderSettings settings =
            PublicApiPayloadBuilderCtrl.getHeaderSettings(config.Id);
        System.assertEquals('ApiKeyHeader', settings.authMode);
        System.assertEquals('application/json', settings.contentType);
        System.assertEquals('X-API-KEY', settings.headerName);
        System.assertEquals('abc123', settings.headerValue);
        System.assertEquals('{"X-Custom":"value"}', settings.additionalHeadersJson);
    }

    @IsTest
    static void testProvisionWebhookDomainReturnsUpdatedHeaderSettings() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'header-builder-test-key-2',
            Outbound_Webhook_URL__c = 'https://example.com/webhook'
        );
        insert config;

        Test.setMock(HttpCalloutMock.class, new MetadataApiMock(
            200,
            metadataApiSuccess('PublicApiWebhook_Example')
        ));
        PublicApiConfigProvisioningService.sessionIdOverride = 'test-session-id';

        Test.startTest();
        PublicApiPayloadBuilderCtrl.HeaderSettings settings =
            PublicApiPayloadBuilderCtrl.provisionWebhookDomain(config.Id);
        Test.stopTest();

        System.assertEquals('https://example.com', settings.outboundRemoteSiteDomain);
        System.assertEquals('PublicApiWebhook_Example', settings.outboundRemoteSiteName);
        System.assertEquals(PublicApiConfigService.REMOTE_SITE_STATUS_PROVISIONED, settings.outboundRemoteSiteStatus);
        System.assertEquals(null, settings.outboundRemoteSiteLastError);
        System.assertNotEquals(null, settings.outboundRemoteSiteLastProvisionedAt);
        PublicApiConfigProvisioningService.sessionIdOverride = null;
    }

    @IsTest
    static void testSavePayloadSettingsRejectsInvalidJson() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'invalid-json-key'
        );
        insert config;

        try {
            PublicApiPayloadBuilderCtrl.savePayloadSettings(
                config.Id,
                true,
                'PublicApi_Submission__c',
                null,
                true,
                'Status__c',
                'Converted',
                '{ bad }',
                '[]'
            );
            System.assert(false, 'Expected AuraHandledException for invalid JSON.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid JSON'));
        }
    }

    @IsTest
    static void testSavePayloadSettingsRejectsInvalidTriggerValue() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'invalid-trigger-value-key'
        );
        insert config;

        try {
            PublicApiPayloadBuilderCtrl.savePayloadSettings(
                config.Id,
                true,
                'PublicApi_Submission__c',
                null,
                true,
                'Created_By_PublicApi_API__c',
                'maybe',
                '[]',
                '[]'
            );
            System.assert(false, 'Expected AuraHandledException for invalid trigger values.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Select valid outbound trigger values'));
        }
    }

    @IsTest
    static void testSavePayloadSettingsRejectsInvalidRelatedRecordConfiguration() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'invalid-related-json-key'
        );
        insert config;

        try {
            PublicApiPayloadBuilderCtrl.savePayloadSettings(
                config.Id,
                true,
                'PublicApi_Submission__c',
                '[' +
                    '{"targetLookupField":"Status__c","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName"}' +
                ']',
                true,
                'Status__c',
                'Converted',
                '[]',
                '[]'
            );
            System.assert(false, 'Expected AuraHandledException for invalid related record configuration.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('lookup or master-detail'));
        }
    }

    @IsTest
    static void testSaveHeaderSettingsRejectsInvalidJson() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'invalid-header-json-key'
        );
        insert config;

        try {
            PublicApiPayloadBuilderCtrl.saveHeaderSettings(
                config.Id,
                'None',
                'application/json',
                null,
                null,
                '{ bad }'
            );
            System.assert(false, 'Expected AuraHandledException for invalid header JSON.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid JSON'));
        }
    }

    private static String metadataApiSuccess(String fullName) {
        return '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">' +
            '<soapenv:Body>' +
            '<createMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata">' +
            '<result>' +
            '<success>true</success>' +
            '<fullName>' + fullName + '</fullName>' +
            '</result>' +
            '</createMetadataResponse>' +
            '</soapenv:Body>' +
            '</soapenv:Envelope>';
    }
}
