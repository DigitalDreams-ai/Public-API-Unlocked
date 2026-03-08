@IsTest
private class PublicApiPayloadBuilderCtrlTest {
    @IsTest
    static void testPayloadSettingsRoundTrip() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'payload-builder-test-key'
        );
        insert config;

        PublicApiPayloadBuilderCtrl.PayloadSettings initialSettings =
            PublicApiPayloadBuilderCtrl.getPayloadSettings(config.Id);
        System.assertNotEquals(null, initialSettings);
        System.assertNotEquals(null, initialSettings.defaultInboundJson);
        System.assertNotEquals(null, initialSettings.defaultOutboundJson);

        String inboundJson =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';
        String outboundJson =
            '[{"externalKey":"createdDate","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":1}]';

        PublicApiPayloadBuilderCtrl.savePayloadSettings(
            config.Id,
            false,
            'PublicApi_Submission__c',
            true,
            'Status__c',
            'Converted',
            inboundJson,
            outboundJson
        );

        PublicApi_Integration_Config__c updated = [
            SELECT Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Target_Object_API_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :config.Id
        ];
        System.assertEquals(inboundJson, updated.Inbound_Payload_Configuration__c);
        System.assertEquals(outboundJson, updated.Outbound_Payload_Configuration__c);
        System.assertEquals(true, updated.Outbound_Trigger_Enabled__c);
        System.assertEquals('Status__c', updated.Outbound_Trigger_Field_Name__c);
        System.assertEquals('Converted', updated.Outbound_Trigger_Field_Values__c);
        System.assertEquals('PublicApi_Submission__c', updated.Target_Object_API_Name__c);
        System.assertEquals(false, updated.Sync_Inbound_And_Outbound__c);
    }

    @IsTest
    static void testGetTriggerMetadata() {
        List<String> fieldNames = PublicApiPayloadBuilderCtrl.getTriggerFieldNames('PublicApi_Submission__c');
        System.assertEquals(true, fieldNames.contains('Status__c'));

        List<String> fieldValues = PublicApiPayloadBuilderCtrl.getTriggerFieldValues(
            'PublicApi_Submission__c',
            'Created_By_PublicApi_API__c'
        );
        System.assertEquals(new List<String>{ 'true', 'false' }, fieldValues);
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
}
