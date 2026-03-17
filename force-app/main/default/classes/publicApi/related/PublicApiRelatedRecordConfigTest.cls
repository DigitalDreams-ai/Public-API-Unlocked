@IsTest
private class PublicApiRelatedRecordConfigTest {
    @IsTest
    static void testParseRuleParsesConfiguredObject() {
        PublicApiRelatedRecordConfig.Rule rule = PublicApiRelatedRecordConfig.parseRule(
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"UseNewest",' +
                '"createMappings":[{"sourceKey":"email","fieldName":"PersonEmail"}]' +
            '}'
        );

        System.assertNotEquals(null, rule);
        System.assertEquals('AccountId', rule.targetLookupField);
        System.assertEquals('Account', rule.relatedObjectApiName);
        System.assertEquals('Name', rule.matchFieldName);
        System.assertEquals('accountName', rule.sourceKey);
        System.assertEquals(true, rule.createIfMissing);
        System.assertEquals('UseNewest', rule.onMultipleMatches);
        System.assertEquals(1, rule.createMappings.size());
        System.assertEquals('email', rule.createMappings[0].sourceKey);
        System.assertEquals('PersonEmail', rule.createMappings[0].fieldName);
    }

    @IsTest
    static void testParseRuleRejectsNonObjectOrArrayJson() {
        try {
            PublicApiRelatedRecordConfig.parseRule('"bad"');
            System.assert(false, 'Expected invalid config to be rejected.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('JSON object'));
        }
    }

    @IsTest
    static void testParseRuleRejectsLegacyArrayJson() {
        try {
            PublicApiRelatedRecordConfig.parseRule(
                '[' +
                    '{"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":true}' +
                ']'
            );
            System.assert(false, 'Expected legacy array config to be rejected.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('JSON object'));
        }
    }

    @IsTest
    static void testGetConfiguredSourceKeysIncludesCreateMappings() {
        Set<String> keys = PublicApiRelatedRecordConfig.getConfiguredSourceKeys(
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,' +
                '"createMappings":[{"sourceKey":"email","fieldName":"PersonEmail"},' +
                '{"sourceKey":"phone","fieldName":"Phone"}]' +
            '}'
        );

        System.assertEquals(new Set<String>{ 'accountName', 'email', 'phone' }, keys);
    }

    @IsTest
    static void testSerializeRuleReturnsObjectJson() {
        PublicApiRelatedRecordConfig.Rule rule = new PublicApiRelatedRecordConfig.Rule();
        rule.targetLookupField = 'AccountId';
        rule.relatedObjectApiName = 'Account';
        rule.matchFieldName = 'Name';
        rule.sourceKey = 'accountName';
        rule.createIfMissing = true;
        rule.onMultipleMatches = 'Error';
        PublicApiRelatedRecordConfig.CreateFieldMapping mapping =
            new PublicApiRelatedRecordConfig.CreateFieldMapping();
        mapping.sourceKey = 'email';
        mapping.fieldName = 'PersonEmail';
        rule.createMappings = new List<PublicApiRelatedRecordConfig.CreateFieldMapping>{ mapping };

        String serialized = PublicApiRelatedRecordConfig.serializeRule(rule);
        System.assert(serialized.startsWith('{'));
        System.assert(serialized.contains('"targetLookupField":"AccountId"'));
        System.assert(serialized.contains('"sourceKey":"email"'));
    }
}

