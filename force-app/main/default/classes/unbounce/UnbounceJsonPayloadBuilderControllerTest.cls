@IsTest
private class UnbounceJsonPayloadBuilderControllerTest {
    @TestSetup
    static void setupData() {
        insert new Unbounce_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'builder-test-key'
        );
    }

    @IsTest
    static void testGetPayloadSettings_ReturnsDefaultsAndFieldReferences() {
        UnbounceJsonPayloadBuilderController.PayloadSettings settings =
            UnbounceJsonPayloadBuilderController.getPayloadSettings(getConfigId());

        System.assertEquals(true, settings.syncInboundAndOutbound);
        System.assert(settings.defaultJson.contains('"inbound"'));
        System.assert(settings.defaultJson.contains('"outbound"'));
        System.assert(settings.availableFieldReferences.size() > 0);
        for (String reference : settings.availableFieldReferences) {
            System.assertEquals(true, reference.startsWith('$intake.'));
        }
    }

    @IsTest
    static void testSaveAndGetPayloadSettings() {
        Id configId = getConfigId();
        String configuration =
            '{' +
                '"inbound":[{"externalKey":"preferred_language","value":"$intake.litify_pm__Description__c","sortOrder":1}],' +
                '"outbound":[{"externalKey":"preferredLanguage","value":"$intake.litify_pm__Description__c","sortOrder":1}]' +
            '}';

        Test.startTest();
        UnbounceJsonPayloadBuilderController.savePayloadSettings(configId, true, configuration);
        Test.stopTest();

        UnbounceJsonPayloadBuilderController.PayloadSettings settings =
            UnbounceJsonPayloadBuilderController.getPayloadSettings(configId);
        System.assertEquals(true, settings.syncInboundAndOutbound);
        System.assertEquals(configuration, settings.configurationJson);
    }

    @IsTest
    static void testSavePayloadSettings_RejectsUnknownFieldReference() {
        try {
            UnbounceJsonPayloadBuilderController.savePayloadSettings(
                getConfigId(),
                true,
                '{"inbound":[{"externalKey":"bad","value":"$intake.Does_Not_Exist__c","sortOrder":1}],"outbound":[]}'
            );
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Unknown Intake field reference'));
        }
    }

    @IsTest
    static void testSavePayloadSettings_RejectsInvalidJsonShape() {
        try {
            UnbounceJsonPayloadBuilderController.savePayloadSettings(
                getConfigId(),
                true,
                '{"bad":true}'
            );
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Mappings configuration'));
        }
    }

    @IsTest
    static void testSaveAndGetHeaderSettings() {
        Id configId = getConfigId();
        String configuration = '{"X-Environment":"Beta","X-Source-System":"Salesforce"}';

        Test.startTest();
        UnbounceJsonPayloadBuilderController.saveHeaderSettings(
            configId,
            'BearerToken',
            'application/json',
            'Authorization',
            'test-token',
            configuration
        );
        Test.stopTest();

        UnbounceJsonPayloadBuilderController.HeaderSettings settings =
            UnbounceJsonPayloadBuilderController.getHeaderSettings(configId);
        System.assertEquals('BearerToken', settings.authMode);
        System.assertEquals('application/json', settings.contentType);
        System.assertEquals('Authorization', settings.headerName);
        System.assertEquals('test-token', settings.headerValue);
        System.assertEquals(configuration, settings.additionalHeadersJson);
    }

    @IsTest
    static void testSaveHeaderSettings_AllowsArrayJson() {
        Id configId = getConfigId();
        String configuration = '[{"name":"X-One","value":"1"},{"name":"X-Two","value":"2"}]';

        Test.startTest();
        UnbounceJsonPayloadBuilderController.saveHeaderSettings(
            configId,
            'ApiKeyHeader',
            'application/json; charset=UTF-8',
            'X-API-KEY',
            'abc123',
            configuration
        );
        Test.stopTest();

        UnbounceJsonPayloadBuilderController.HeaderSettings settings =
            UnbounceJsonPayloadBuilderController.getHeaderSettings(configId);
        System.assertEquals('ApiKeyHeader', settings.authMode);
        System.assertEquals('application/json; charset=UTF-8', settings.contentType);
        System.assertEquals('X-API-KEY', settings.headerName);
        System.assertEquals('abc123', settings.headerValue);
        System.assertEquals(configuration, settings.additionalHeadersJson);
    }

    @IsTest
    static void testSaveHeaderSettings_RejectsPrimitiveJson() {
        try {
            UnbounceJsonPayloadBuilderController.saveHeaderSettings(
                getConfigId(),
                'None',
                'application/json',
                null,
                null,
                '"bad"'
            );
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Configuration must be a JSON object or array'));
        }
    }

    @IsTest
    static void testController_NullRecordIdBranches() {
        System.assertEquals(null, UnbounceJsonPayloadBuilderController.getPayloadSettings(null));
        System.assertEquals(null, UnbounceJsonPayloadBuilderController.getHeaderSettings(null));

        try {
            UnbounceJsonPayloadBuilderController.savePayloadSettings(null, true, '{}');
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Record ID is required'));
        }

        try {
            UnbounceJsonPayloadBuilderController.saveHeaderSettings(
                null,
                'None',
                'application/json',
                null,
                null,
                '{}'
            );
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Record ID is required'));
        }
    }

    private static Id getConfigId() {
        return [
            SELECT Id
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = 'builder-test-key'
            LIMIT 1
        ].Id;
    }
}
