@IsTest
private class PublicApiRelatedRecordConfigTest {
    @IsTest
    static void testParseRulesParsesConfiguredRows() {
        List<PublicApiRelatedRecordConfig.Rule> rules = PublicApiRelatedRecordConfig.parseRules(
            '[' +
                '{"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"UseNewest",' +
                '"createMappings":[{"sourceKey":"email","fieldName":"PersonEmail"}]}' +
            ']'
        );

        System.assertEquals(1, rules.size());
        System.assertEquals('AccountId', rules[0].targetLookupField);
        System.assertEquals('Account', rules[0].relatedObjectApiName);
        System.assertEquals('Name', rules[0].matchFieldName);
        System.assertEquals('accountName', rules[0].sourceKey);
        System.assertEquals(true, rules[0].createIfMissing);
        System.assertEquals('UseNewest', rules[0].onMultipleMatches);
        System.assertEquals(1, rules[0].createMappings.size());
        System.assertEquals('email', rules[0].createMappings[0].sourceKey);
        System.assertEquals('PersonEmail', rules[0].createMappings[0].fieldName);
    }

    @IsTest
    static void testParseRulesRejectsNonArrayJson() {
        try {
            PublicApiRelatedRecordConfig.parseRules('{"targetLookupField":"AccountId"}');
            System.assert(false, 'Expected invalid config to be rejected.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('JSON array'));
        }
    }

    @IsTest
    static void testGetConfiguredSourceKeysIncludesCreateMappings() {
        Set<String> keys = PublicApiRelatedRecordConfig.getConfiguredSourceKeys(
            '[' +
                '{"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,' +
                '"createMappings":[{"sourceKey":"email","fieldName":"PersonEmail"},' +
                '{"sourceKey":"phone","fieldName":"Phone"}]}' +
            ']'
        );

        System.assertEquals(new Set<String>{ 'accountName', 'email', 'phone' }, keys);
    }
}
