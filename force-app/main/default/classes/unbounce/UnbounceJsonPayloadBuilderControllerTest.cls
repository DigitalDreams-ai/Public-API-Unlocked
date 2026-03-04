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
    static void testGetDefaultPayloadSchema_ReturnsExpectedPaths() {
        String schema = UnbounceJsonPayloadBuilderController.getDefaultPayloadSchema();
        System.assert(schema.contains('"firstName"'));
        System.assert(schema.contains('"$.firstName"'));
        System.assert(schema.contains('"$.createdDate"'));
    }

    @IsTest
    static void testSaveAndGetConfiguration() {
        Id configId = getConfigId();
        String configuration = '{"lead":{"email":"$.email"},"event":"status_changed"}';

        Test.startTest();
        UnbounceJsonPayloadBuilderController.saveConfiguration(configId, configuration);
        Test.stopTest();

        System.assertEquals(
            configuration,
            UnbounceJsonPayloadBuilderController.getConfiguration(configId)
        );
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
    static void testSaveConfiguration_RejectsNonObjectJson() {
        Id configId = getConfigId();
        try {
            UnbounceJsonPayloadBuilderController.saveConfiguration(configId, '["bad"]');
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Configuration must be a JSON object'));
        }
    }

    @IsTest
    static void testSaveConfiguration_RejectsInvalidJson() {
        Id configId = getConfigId();
        try {
            UnbounceJsonPayloadBuilderController.saveConfiguration(configId, '{"bad":');
            System.assert(false, 'Expected an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid JSON'));
        }
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
        Id configId = getConfigId();
        try {
            UnbounceJsonPayloadBuilderController.saveHeaderSettings(
                configId,
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
    static void testSaveConfiguration_ClearsConfigurationWhenBlank() {
        Id configId = getConfigId();
        UnbounceJsonPayloadBuilderController.saveConfiguration(configId, '{"lead":{"email":"$.email"}}');

        Test.startTest();
        UnbounceJsonPayloadBuilderController.saveConfiguration(configId, null);
        Test.stopTest();

        System.assertEquals(null, UnbounceJsonPayloadBuilderController.getConfiguration(configId));
    }

    @IsTest
    static void testSaveHeaderSettings_ClearsConfigurationWhenBlank() {
        Id configId = getConfigId();
        UnbounceJsonPayloadBuilderController.saveHeaderSettings(
            configId,
            'None',
            'application/json',
            null,
            null,
            '{"X-Test":"1"}'
        );

        Test.startTest();
        UnbounceJsonPayloadBuilderController.saveHeaderSettings(
            configId,
            null,
            null,
            null,
            null,
            null
        );
        Test.stopTest();

        UnbounceJsonPayloadBuilderController.HeaderSettings settings =
            UnbounceJsonPayloadBuilderController.getHeaderSettings(configId);
        System.assertEquals(null, settings.authMode);
        System.assertEquals(null, settings.contentType);
        System.assertEquals(null, settings.headerName);
        System.assertEquals(null, settings.headerValue);
        System.assertEquals(null, settings.additionalHeadersJson);
    }

    @IsTest
    static void testController_NullRecordIdBranches() {
        System.assertEquals(null, UnbounceJsonPayloadBuilderController.getConfiguration(null));
        System.assertEquals(null, UnbounceJsonPayloadBuilderController.getHeaderSettings(null));

        try {
            UnbounceJsonPayloadBuilderController.saveConfiguration(null, '{}');
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

    @IsTest
    static void testPayloadTemplateService_ResolvesConfiguredTemplate() {
        Map<String, Object> sourcePayload = new Map<String, Object>{
            'firstName' => 'Jane',
            'lastName' => 'Smith',
            'email' => 'jane@example.com',
            'gclid' => 'g-123',
            'createdDate' => '2026-03-03T00:00:00.000Z'
        };
        Map<String, Object> result = UnbouncePayloadTemplateService.applyTemplateConfiguration(
            '{"lead":{"first_name":"$.firstName","email":"$.email"},"source":"salesforce"}',
            sourcePayload
        );

        System.assertEquals('salesforce', result.get('source'));
        Map<String, Object> lead = (Map<String, Object>) result.get('lead');
        System.assertEquals('Jane', lead.get('first_name'));
        System.assertEquals('jane@example.com', lead.get('email'));
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
