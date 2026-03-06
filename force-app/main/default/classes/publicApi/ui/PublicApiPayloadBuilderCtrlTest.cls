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
        System.assertNotEquals(null, initialSettings.defaultJson);

        String configJson =
            '{"inbound":[{"externalKey":"first_name","value":"$PublicApi_Submission__c.First_Name__c","sortOrder":1}],' +
            '"outbound":[{"externalKey":"first_name","value":"$PublicApi_Submission__c.First_Name__c","sortOrder":1}]}';

        PublicApiPayloadBuilderCtrl.savePayloadSettings(
            config.Id,
            true,
            'PublicApi_Submission__c',
            'PublicApi_Submission__c',
            configJson
        );

        PublicApi_Integration_Config__c updated = [
            SELECT Outbound_Payload_Configuration__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :config.Id
        ];
        System.assertEquals(configJson, updated.Outbound_Payload_Configuration__c);
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
                'PublicApi_Submission__c',
                '{ bad }'
            );
            System.assert(false, 'Expected AuraHandledException for invalid JSON.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid JSON'));
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
