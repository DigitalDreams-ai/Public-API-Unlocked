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
            API_Key__c = 'payload-builder-test-key',
            Endpoint_Path__c = '/payload-builder-test'
        );
        insert config;

        String triggerFieldName = selectPreferredTriggerFieldName('PublicApi_Submission__c');
        String triggerFieldValues = selectValidTriggerValues('PublicApi_Submission__c', triggerFieldName);

        PublicApiPayloadBuilderCtrl.PayloadSettings initialSettings =
            PublicApiPayloadBuilderCtrl.getPayloadSettings(config.Id);
        System.assertNotEquals(null, initialSettings);
        System.assertEquals('/payload-builder-test', initialSettings.endpointPath);
        System.assertNotEquals(null, initialSettings.defaultInboundJson);
        System.assertNotEquals(null, initialSettings.defaultOutboundJson);
        System.assertNotEquals(null, initialSettings.availableTargetRecordTypeDeveloperNames);
        System.assertNotEquals(null, initialSettings.availableRequiredInboundFieldNames);

        String targetRecordTypeDeveloperName = selectPreferredRecordTypeDeveloperName('PublicApi_Submission__c');
        String relatedRecordTypeDeveloperName =
            selectPreferredRecordTypeDeveloperName('PublicApi_Integration_Config__c');
        String relatedRecordTypeSegment = String.isBlank(relatedRecordTypeDeveloperName)
            ? ''
            : '"createRecordTypeDeveloperName":"' + relatedRecordTypeDeveloperName + '",';

        String inboundJson =
            '[' +
                '{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1,"sourceType":"IncomingKey"},' +
                '{"sourceType":"LiteralValue","literalValue":"application/json","value":"$PublicApi_Submission__c.Request_Content_Type__c","sortOrder":2}' +
            ']';
        String outboundJson =
            '[{"externalKey":"createdDate","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":1}]';
        String relatedRecordJson =
            '{' +
                '"targetLookupField":"PublicApi_Integration_Config__c","relatedObjectApiName":"PublicApi_Integration_Config__c",' +
                '"matchFieldName":"API_Key__c","sourceKey":"configKey","createIfMissing":true,"onMultipleMatches":"Error",' +
                relatedRecordTypeSegment +
                '"createMappings":[{"sourceKey":"configKey","fieldName":"API_Key__c"}]' +
            '}';

        PublicApiPayloadBuilderCtrl.savePayloadSettings(
            config.Id,
            false,
            '/payload-builder-updated',
            'PublicApi_Submission__c',
            targetRecordTypeDeveloperName,
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
                   Endpoint_Path__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Target_Record_Type_Developer_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :config.Id
        ];
        System.assertEquals(inboundJson, updated.Inbound_Payload_Configuration__c);
        System.assertEquals(outboundJson, updated.Outbound_Payload_Configuration__c);
        System.assertEquals('/payload-builder-updated', updated.Endpoint_Path__c);
        System.assertEquals(true, updated.Outbound_Trigger_Enabled__c);
        System.assertEquals(triggerFieldName, updated.Outbound_Trigger_Field_Name__c);
        System.assertEquals(triggerFieldValues, updated.Outbound_Trigger_Field_Values__c);
        System.assertEquals(relatedRecordJson, updated.Related_Record_Configuration__c);
        System.assertEquals('PublicApi_Submission__c', updated.Target_Object_API_Name__c);
        System.assertEquals(targetRecordTypeDeveloperName, updated.Target_Record_Type_Developer_Name__c);
        System.assertEquals(false, updated.Sync_Inbound_And_Outbound__c);
    }

    @IsTest
    static void testGetTriggerMetadata() {
        List<String> fieldNames = PublicApiPayloadBuilderCtrl.getTriggerFieldNames('PublicApi_Submission__c');
        System.assertEquals(true, fieldNames.size() > 0);
        System.assertEquals(true, fieldNames.contains(selectPreferredTriggerFieldName('PublicApi_Submission__c')));

        String constrainedTriggerFieldName =
            selectValueConstrainedTriggerFieldName('PublicApi_Submission__c');
        if (constrainedTriggerFieldName != null) {
            List<String> fieldValues = PublicApiPayloadBuilderCtrl.getTriggerFieldValues(
                'PublicApi_Submission__c',
                constrainedTriggerFieldName
            );
            System.assertEquals(true, fieldValues.size() > 0);
        }

        List<String> lookupFields = PublicApiPayloadBuilderCtrl.getLookupFieldNames('PublicApi_Submission__c');
        System.assertNotEquals(null, lookupFields);
        List<String> relatedObjects = PublicApiPayloadBuilderCtrl.getRelatedObjectApiNames('Task');
        System.assertNotEquals(null, relatedObjects);

        if (!relatedObjects.isEmpty()) {
            List<String> taskLookupFields =
                PublicApiPayloadBuilderCtrl.getLookupFieldNamesForRelatedObject('Task', relatedObjects[0]);
            System.assertNotEquals(null, taskLookupFields);
        }

        List<String> requiredCreateFields = PublicApiPayloadBuilderCtrl.getRequiredCreateFieldNames('Task');
        System.assertNotEquals(null, requiredCreateFields);
    }

    @IsTest
    static void testGetRecordTypeMetadata() {
        List<String> recordTypeDeveloperNames =
            PublicApiPayloadBuilderCtrl.getRecordTypeDeveloperNames('Account');
        System.assertNotEquals(null, recordTypeDeveloperNames);
        System.assertEquals(true, recordTypeDeveloperNames.size() > 0);
    }

    @IsTest
    static void testPayloadSettingsRoundTripPersistsRelatedCreateRecordType() {
        String relatedRecordTypeDeveloperName = selectPreferredRecordTypeDeveloperName('Account');
        if (String.isBlank(relatedRecordTypeDeveloperName)) {
            System.assertEquals(null, relatedRecordTypeDeveloperName);
            return;
        }

        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'payload-builder-related-record-type-key',
            Endpoint_Path__c = '/payload-builder-related-record-type'
        );
        insert config;

        String triggerFieldName = selectPreferredTriggerFieldName('PublicApi_Submission__c');
        String triggerFieldValues = selectValidTriggerValues('PublicApi_Submission__c', triggerFieldName);

        PublicApiPayloadBuilderCtrl.savePayloadSettings(
            config.Id,
            true,
            '/payload-builder-related-record-type-updated',
            'Task',
            null,
            '{' +
                '"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"createRecordTypeDeveloperName":"' +
                relatedRecordTypeDeveloperName + '","onMultipleMatches":"Error"' +
            '}',
            true,
            triggerFieldName,
            triggerFieldValues,
            '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
            '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]'
        );

        PublicApi_Integration_Config__c updated = [
            SELECT Related_Record_Configuration__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :config.Id
        ];
        System.assert(updated.Related_Record_Configuration__c.contains(
            '"createRecordTypeDeveloperName":"' + relatedRecordTypeDeveloperName + '"'
        ));
    }

    private static String selectPreferredTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadBuilderCtrl.getTriggerFieldNames(objectApiName);
        System.assertEquals(true, fieldNames.size() > 0, 'Expected at least one trigger field.');
        if (fieldNames.contains('Processing_Status__c')) {
            return 'Processing_Status__c';
        }
        if (fieldNames.contains('Created_By_PublicApi_API__c')) {
            return 'Created_By_PublicApi_API__c';
        }
        if (fieldNames.contains('Status__c')) {
            return 'Status__c';
        }
        return fieldNames[0];
    }

    private static String selectValueConstrainedTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadBuilderCtrl.getTriggerFieldNames(objectApiName);
        for (String fieldName : fieldNames) {
            List<String> values =
                PublicApiPayloadBuilderCtrl.getTriggerFieldValues(objectApiName, fieldName);
            if (!values.isEmpty()) {
                return fieldName;
            }
        }
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
            API_Key__c = 'invalid-json-key',
            Endpoint_Path__c = '/invalid-json'
        );
        insert config;

        try {
            PublicApiPayloadBuilderCtrl.savePayloadSettings(
                config.Id,
                true,
                '/invalid-json-updated',
                'PublicApi_Submission__c',
                null,
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
            API_Key__c = 'invalid-trigger-value-key',
            Endpoint_Path__c = '/invalid-trigger-value'
        );
        insert config;

        String constrainedTriggerFieldName =
            selectValueConstrainedTriggerFieldName('PublicApi_Submission__c');
        if (constrainedTriggerFieldName == null) {
            System.assert(true, 'No constrained trigger field is available in this test context.');
            return;
        }

        try {
            PublicApiPayloadBuilderCtrl.savePayloadSettings(
                config.Id,
                true,
                '/invalid-trigger-value-updated',
                'PublicApi_Submission__c',
                null,
                null,
                true,
                constrainedTriggerFieldName,
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
            API_Key__c = 'invalid-related-json-key',
            Endpoint_Path__c = '/invalid-related-json'
        );
        insert config;

        try {
            PublicApiPayloadBuilderCtrl.savePayloadSettings(
                config.Id,
                true,
                '/invalid-related-json-updated',
                'PublicApi_Submission__c',
                null,
                '{' +
                    '"targetLookupField":"Status__c","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName"' +
                '}',
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
    static void testSavePayloadSettingsRejectsInvalidTargetRecordType() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'invalid-target-record-type-key',
            Endpoint_Path__c = '/invalid-target-record-type'
        );
        insert config;

        try {
            PublicApiPayloadBuilderCtrl.savePayloadSettings(
                config.Id,
                true,
                '/invalid-target-record-type-updated',
                'Account',
                'DoesNotExist',
                null,
                true,
                null,
                null,
                '[{"externalKey":"name","value":"$Account.Name","sortOrder":1}]',
                '[{"externalKey":"name","value":"$Account.Name","sortOrder":1}]'
            );
            System.assert(false, 'Expected AuraHandledException for invalid target record type.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Select a valid target record type'));
        }
    }

    private static String selectPreferredRecordTypeDeveloperName(String objectApiName) {
        List<String> developerNames = PublicApiPayloadBuilderCtrl.getRecordTypeDeveloperNames(objectApiName);
        if (developerNames.isEmpty()) {
            return null;
        }
        if (developerNames.contains('Business')) {
            return 'Business';
        }
        if (developerNames.contains('Individual')) {
            return 'Individual';
        }
        return developerNames[0];
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
