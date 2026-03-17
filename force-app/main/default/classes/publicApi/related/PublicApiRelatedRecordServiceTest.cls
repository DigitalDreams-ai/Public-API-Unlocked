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
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error"' +
            '}'
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
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error",' +
                createMappingsJson + '}' +
            '}'
        );

        SObject created = queryAccount(target.AccountId, accountLastNameFieldName, true);
        System.assert(String.isNotBlank(String.valueOf(created.get('Name'))));
        System.assertEquals('Phoenix', created.get('Site'));
        if (accountLastNameFieldName != null) {
            System.assertEquals('Created Account', created.get(accountLastNameFieldName));
        }
    }

    @IsTest
    static void testApplyRelatedRecordRulesCreatesMissingAccountWithoutExplicitNameMapping() {
        Contact target = new Contact(LastName = 'Jones');
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'Taylor',
            'lastName' => 'Swift',
            'email' => 'taylor.swift.related@example.com'
        };

        PublicApiRelatedRecordService.applyRelatedRecordRules(
            target,
            payload,
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"email","createIfMissing":true,"onMultipleMatches":"Error"' +
            '}'
        );

        String accountLastNameFieldName = getAccountLastNameFieldName();
        SObject created = queryAccount(target.AccountId, accountLastNameFieldName, false);
        System.assert(String.isNotBlank(String.valueOf(created.get('Name'))));
        if (accountLastNameFieldName != null) {
            System.assertEquals('Swift', created.get(accountLastNameFieldName));
        }
    }

    @IsTest
    static void testApplyRelatedRecordRulesUsesConfiguredRelatedRecordTypeWhenAvailable() {
        Id businessRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        Contact target = new Contact(LastName = 'Configured');
        Map<String, Object> payload = new Map<String, Object>{
            'accountName' => 'Configured Related Account',
            'accountLastName' => 'Configured Related Account'
        };
        String configuredRecordTypeSegment =
            businessRecordTypeId == null
                ? ''
                : '"createRecordTypeDeveloperName":"Business",';

        PublicApiRelatedRecordService.applyRelatedRecordRules(
            target,
            payload,
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,' +
                configuredRecordTypeSegment +
                '"onMultipleMatches":"Error"' +
            '}'
        );

        SObject created = queryAccount(target.AccountId, null, false);
        System.assertNotEquals(null, created.get('Id'));
        if (businessRecordTypeId != null && accountSupportsRecordTypes()) {
            System.assertEquals(businessRecordTypeId, created.get('RecordTypeId'));
        }
    }

    @IsTest
    static void testApplyRelatedRecordRulesUsesOldestMatchWhenConfigured() {
        Account oldestAccount = createAccount('Duplicate Match');
        insert oldestAccount;
        Account newestAccount = createAccount('Duplicate Match');
        insert newestAccount;

        Test.setCreatedDate(oldestAccount.Id, Datetime.newInstance(2024, 1, 1, 8, 0, 0));
        Test.setCreatedDate(newestAccount.Id, Datetime.newInstance(2024, 1, 2, 8, 0, 0));

        Contact target = new Contact(LastName = 'Oldest');
        Map<String, Object> payload = new Map<String, Object>{
            'accountName' => 'Duplicate Match'
        };

        PublicApiRelatedRecordService.applyRelatedRecordRules(
            target,
            payload,
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":false,"onMultipleMatches":"UseOldest"' +
            '}'
        );

        System.assertEquals(oldestAccount.Id, target.AccountId);
    }

    @IsTest
    static void testApplyRelatedRecordRulesUsesNewestMatchWhenConfigured() {
        Account oldestAccount = createAccount('Duplicate Match');
        insert oldestAccount;
        Account newestAccount = createAccount('Duplicate Match');
        insert newestAccount;

        Test.setCreatedDate(oldestAccount.Id, Datetime.newInstance(2024, 1, 1, 8, 0, 0));
        Test.setCreatedDate(newestAccount.Id, Datetime.newInstance(2024, 1, 2, 8, 0, 0));

        Contact target = new Contact(LastName = 'Newest');
        Map<String, Object> payload = new Map<String, Object>{
            'accountName' => 'Duplicate Match'
        };

        PublicApiRelatedRecordService.applyRelatedRecordRules(
            target,
            payload,
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":false,"onMultipleMatches":"UseNewest"' +
            '}'
        );

        System.assertEquals(newestAccount.Id, target.AccountId);
    }

    @IsTest
    static void testDeferredRulesReturnSingleDeferredAccountRule() {
        String configJson =
            '{' +
                '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                '"sourceKey":"accountName","createIfMissing":true,"onMultipleMatches":"Error"' +
            '}';

        String immediateJson = PublicApiRelatedRecordService.getImmediateRuleJson(configJson);
        String deferredJson = PublicApiRelatedRecordService.getDeferredRuleJson(configJson);

        System.assertEquals(true, String.isBlank(immediateJson));
        System.assertEquals('Account', PublicApiRelatedRecordConfig.parseRule(deferredJson).relatedObjectApiName);
    }

    @IsTest
    static void testImmediateRulesReturnSingleImmediateNonAccountRule() {
        String configJson =
            '{' +
                '"targetLookupField":"WhoId","relatedObjectApiName":"Lead","matchFieldName":"Email",' +
                '"sourceKey":"email","createIfMissing":false,"onMultipleMatches":"Error"' +
            '}';

        String immediateJson = PublicApiRelatedRecordService.getImmediateRuleJson(configJson);
        String deferredJson = PublicApiRelatedRecordService.getDeferredRuleJson(configJson);

        System.assertEquals('Lead', PublicApiRelatedRecordConfig.parseRule(immediateJson).relatedObjectApiName);
        System.assertEquals(true, String.isBlank(deferredJson));
    }

    @IsTest
    static void testValidateRulesRejectsInvalidLookupField() {
        try {
            PublicApiRelatedRecordService.validateRules(
                '{' +
                    '"targetLookupField":"LastName","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":false' +
                '}',
                'Contact'
            );
            System.assert(false, 'Expected invalid lookup field to be rejected.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('lookup or master-detail'));
        }
    }

    @IsTest
    static void testValidateRulesRejectsUnsupportedMultiMatchPolicy() {
        try {
            PublicApiRelatedRecordService.validateRules(
                '{' +
                    '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":false,"onMultipleMatches":"UseFirst"' +
                '}',
                'Contact'
            );
            System.assert(false, 'Expected unsupported multiple match policy to be rejected.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('Unsupported related record multiple match policy'));
        }
    }

    @IsTest
    static void testValidateRulesRejectsUnknownCreateRecordType() {
        try {
            PublicApiRelatedRecordService.validateRules(
                '{' +
                    '"targetLookupField":"AccountId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"accountName","createIfMissing":true,"createRecordTypeDeveloperName":"DoesNotExist",' +
                    '"onMultipleMatches":"Error"' +
                '}',
                'Contact'
            );
            System.assert(false, 'Expected unknown related record type to be rejected.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('Unknown related create record type'));
        }
    }

    @IsTest
    static void testApplyRelatedRecordRulesRejectsUnsatisfiedRequiredFieldsBeforeInsert() {
        Task target = new Task(Subject = 'Related Lead');
        Map<String, Object> payload = new Map<String, Object>{
            'email' => 'lead.required@example.com'
        };

        try {
            PublicApiRelatedRecordService.applyRelatedRecordRules(
                target,
                payload,
                '{' +
                    '"targetLookupField":"WhoId","relatedObjectApiName":"Lead","matchFieldName":"Email",' +
                    '"sourceKey":"email","createIfMissing":true,"onMultipleMatches":"Error"' +
                '}'
            );
            System.assert(false, 'Expected required-field validation to fail before DML.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('cannot satisfy required fields'));
            System.assert(e.getMessage().contains('Company'));
            System.assert(e.getMessage().contains('LastName'));
        }
    }

    @IsTest
    static void testStructuralFieldValidationUsesSchemaSemantics() {
        Map<String, Schema.SObjectField> submissionFieldMap =
            PublicApi_Submission__c.SObjectType.getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> accountFieldMap =
            Account.SObjectType.getDescribe().fields.getMap();

        System.assertEquals(
            false,
            PublicApiRelatedRecordService.isStructurallyWritableField(
                submissionFieldMap.get('Name').getDescribe()
            )
        );
        System.assertEquals(
            true,
            PublicApiRelatedRecordService.isStructurallyWritableField(
                Contact.SObjectType.getDescribe().fields.getMap().get('AccountId').getDescribe()
            )
        );
        System.assertEquals(
            true,
            PublicApiRelatedRecordService.isStructurallyQueryableField(
                accountFieldMap.get('Name').getDescribe()
            )
        );
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
        for (String preferredFieldName : new List<String>{ 'LastName' }) {
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

    private static SObject queryAccount(Id accountId, String accountLastNameFieldName, Boolean includeSite) {
        List<String> fieldNames = new List<String>{ 'Id', 'Name' };
        if (accountSupportsRecordTypes()) {
            fieldNames.add('RecordTypeId');
        }
        if (includeSite) {
            fieldNames.add('Site');
        }
        if (String.isNotBlank(accountLastNameFieldName)) {
            fieldNames.add(accountLastNameFieldName);
        }
        return Database.query(
            'SELECT ' + String.join(fieldNames, ', ') + ' FROM Account WHERE Id = :accountId'
        );
    }

    private static Boolean accountSupportsRecordTypes() {
        return Account.SObjectType.getDescribe().fields.getMap().containsKey('RecordTypeId');
    }

}

