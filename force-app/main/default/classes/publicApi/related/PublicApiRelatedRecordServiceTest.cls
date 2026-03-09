@IsTest
private class PublicApiRelatedRecordServiceTest {
    @IsTest
    static void testApplyRelatedRecordRulesUsesExistingAccount() {
        Account existingAccount = createAccount('Existing Account');
        insert existingAccount;

        Contact target = new Contact(LastName = 'Smith');
        Map<String, Object> payload = new Map<String, Object>{
            'accountName' => 'Existing Account'
        };

        PublicApiRelatedRecordService.applyRelatedRecordRules(
            target,
            payload,
            '[' +
                '{"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error"}' +
            ']'
        );

        System.assertEquals(existingAccount.Id, target.AccountId);
        System.assertEquals(1, [SELECT Count() FROM Account WHERE Name = 'Existing Account']);
    }

    @IsTest
    static void testApplyRelatedRecordRulesCreatesMissingAccount() {
        Contact target = new Contact(LastName = 'Jones');
        String accountLastNameFieldName = getAccountLastNameFieldName();
        String createMappingsJson =
            accountLastNameFieldName == null
                ? '"createMappings":[{"sourceKey":"accountSite","fieldName":"Site"}]'
                : '"createMappings":[' +
                    '{"sourceKey":"accountSite","fieldName":"Site"},' +
                    '{"sourceKey":"accountLastName","fieldName":"' + accountLastNameFieldName + '"}' +
                  ']';
        Map<String, Object> payload = new Map<String, Object>{
            'accountName' => 'Created Account',
            'accountSite' => 'Phoenix',
            'accountLastName' => 'Created Account'
        };

        PublicApiRelatedRecordService.applyRelatedRecordRules(
            target,
            payload,
            '[' +
                '{"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error",' +
                createMappingsJson + '}' +
            ']'
        );

        Account created = [SELECT Id, Name, Site FROM Account WHERE Id = :target.AccountId];
        System.assertEquals('Created Account', created.Name);
        System.assertEquals('Phoenix', created.Site);
    }

    @IsTest
    static void testValidateRulesRejectsInvalidLookupField() {
        try {
            PublicApiRelatedRecordService.validateRules(
                '[' +
                    '{"targetLookupField":"LastName","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":false}' +
                ']',
                'Contact'
            );
            System.assert(false, 'Expected invalid lookup field to be rejected.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('lookup or master-detail'));
        }
    }

    @IsTest
    static void testValidateRulesRejectsUnsupportedMultiMatchPolicy() {
        try {
            PublicApiRelatedRecordService.validateRules(
                '[' +
                    '{"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":false,"onMultipleMatches":"UseFirst"}' +
                ']',
                'Contact'
            );
            System.assert(false, 'Expected unsupported multiple match policy to be rejected.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('Unsupported related record multiple match policy'));
        }
    }

    private static Account createAccount(String name) {
        Account accountRecord = new Account(Name = name);
        String lastNameFieldName = getAccountLastNameFieldName();
        if (lastNameFieldName != null) {
            accountRecord.put(lastNameFieldName, name);
        }
        return accountRecord;
    }

    private static String getAccountLastNameFieldName() {
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        for (String preferredFieldName : new List<String>{ 'LastName', 'litify_pm__Last_Name__c' }) {
            if (fieldMap.containsKey(preferredFieldName) &&
                fieldMap.get(preferredFieldName).getDescribe().isCreateable()) {
                return preferredFieldName;
            }
        }

        for (Schema.SObjectField fieldToken : fieldMap.values()) {
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (describe.isCreateable() &&
                describe.getType() == Schema.DisplayType.String &&
                describe.getName().toLowerCase().contains('last')) {
                return describe.getName();
            }
        }
        return null;
    }
}
