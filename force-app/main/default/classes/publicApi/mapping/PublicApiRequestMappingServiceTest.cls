@IsTest
private class PublicApiRequestMappingServiceTest {
    @IsTest
    static void testApplyInboundMappingsSetsStatus() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        Map<String, Object> payload = new Map<String, Object>{ 'status' => 'Converted' };

        String mappingsJson =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            mappingsJson,
            'PublicApi_Submission__c'
        );

        System.assertEquals('Converted', submission.Status__c);
    }

    @IsTest
    static void testBuildOutboundPayloadFromSubmission() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c(Status__c = 'Referred Out');
        insert submission;
        submission = [
            SELECT Id, Status__c, CreatedDate
            FROM PublicApi_Submission__c
            WHERE Id = :submission.Id
        ];

        String mappingsJson =
            '[' +
                '{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1},' +
                '{"externalKey":"createdDate","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":2}' +
            ']';

        Map<String, Object> payload = PublicApiRequestMappingService.buildOutboundPayload(
            submission,
            mappingsJson,
            'PublicApi_Submission__c'
        );

        System.assertEquals('Referred Out', payload.get('status'));
        String createdDate = String.valueOf(payload.get('createdDate'));
        System.assert(String.isNotBlank(createdDate));
        System.assert(createdDate.contains('T'));
        System.assert(createdDate.endsWith('Z'));
    }

    @IsTest
    static void testApplyInboundMappingsSupportsNestedExternalKeys() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        Map<String, Object> payload = new Map<String, Object>{
            'data' => new Map<String, Object>{
                'meta' => new Map<String, Object>{ 'status' => 'Converted' }
            }
        };

        String mappingsJson =
            '[{"externalKey":"meta.status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            mappingsJson,
            'PublicApi_Submission__c'
        );

        System.assertEquals('Converted', submission.Status__c);
    }

    @IsTest
    static void testApplyInboundMappingsParsesBooleanValues() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        String mappingsJson =
            '[' +
                '{"externalKey":"createdByApi","value":"$PublicApi_Submission__c.Created_By_PublicApi_API__c","sortOrder":1}' +
            ']';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            new Map<String, Object>{ 'createdByApi' => 'true' },
            mappingsJson,
            'PublicApi_Submission__c'
        );

        System.assertEquals(true, submission.Created_By_PublicApi_API__c);
    }

    @IsTest
    static void testApplyInboundMappingsLeavesFieldBlankWhenIncomingKeyIsMissing() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        String mappingsJson =
            '[' +
                '{"externalKey":"missingStatus","value":"$PublicApi_Submission__c.Status__c","sortOrder":1,"sourceType":"IncomingKey"}' +
            ']';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            new Map<String, Object>{ 'otherKey' => 'ignored' },
            mappingsJson,
            'PublicApi_Submission__c'
        );

        System.assertEquals(null, submission.Status__c);
    }

    @IsTest
    static void testApplyInboundMappingsUsesLiteralValue() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        String mappingsJson =
            '[' +
                '{"sourceType":"LiteralValue","literalValue":"Manual","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}' +
            ']';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            new Map<String, Object>{ 'status' => 'Ignored' },
            mappingsJson,
            'PublicApi_Submission__c'
        );

        System.assertEquals('Manual', submission.Status__c);
    }

    @IsTest
    static void testApplyInboundMappingsResolvesLookupLiteralValueByName() {
        Account accountRecord = createAccount('Literal Lookup Account');
        insert accountRecord;

        Account childAccount = createAccount('Child Lookup Account');
        String mappingsJson =
            '[' +
                '{"sourceType":"LiteralValue","literalValue":"Literal Lookup Account","value":"$Account.ParentId","sortOrder":1}' +
            ']';

        PublicApiRequestMappingService.applyInboundMappings(
            childAccount,
            new Map<String, Object>{ 'ignored' => 'value' },
            mappingsJson,
            'Account'
        );

        System.assertEquals(accountRecord.Id, childAccount.ParentId);
    }

    @IsTest
    static void testApplyInboundMappingsResolvesLookupIncomingKeyByName() {
        Account accountRecord = createAccount('Incoming Lookup Account');
        insert accountRecord;

        Account childAccount = createAccount('Child Incoming Lookup Account');
        String mappingsJson =
            '[' +
                '{"externalKey":"parentName","sourceType":"IncomingKey","value":"$Account.ParentId","sortOrder":1}' +
            ']';

        PublicApiRequestMappingService.applyInboundMappings(
            childAccount,
            new Map<String, Object>{ 'parentName' => 'Incoming Lookup Account' },
            mappingsJson,
            'Account'
        );

        System.assertEquals(accountRecord.Id, childAccount.ParentId);
    }

    @IsTest
    static void testApplyInboundMappingsPreservesLookupIncomingKeyId() {
        Account accountRecord = createAccount('Existing Parent Account');
        insert accountRecord;

        Account childAccount = createAccount('Child Existing Parent Account');
        String mappingsJson =
            '[' +
                '{"externalKey":"parentId","sourceType":"IncomingKey","value":"$Account.ParentId","sortOrder":1}' +
            ']';

        PublicApiRequestMappingService.applyInboundMappings(
            childAccount,
            new Map<String, Object>{ 'parentId' => accountRecord.Id },
            mappingsJson,
            'Account'
        );

        System.assertEquals(accountRecord.Id, childAccount.ParentId);
    }

    @IsTest
    static void testApplyInboundMappingsRejectsUnmatchedLookupLiteralValue() {
        Account childAccount = createAccount('Child Lookup Error Test');
        String mappingsJson =
            '[' +
                '{"sourceType":"LiteralValue","literalValue":"Missing Lookup Account","value":"$Account.ParentId","sortOrder":1}' +
            ']';

        try {
            PublicApiRequestMappingService.applyInboundMappings(
                childAccount,
                new Map<String, Object>{ 'ignored' => 'value' },
                mappingsJson,
                'Account'
            );
            System.assert(false, 'Expected unmatched lookup literal to throw.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('did not match any Account records by Name'));
        }
    }

    @IsTest
    static void testValidateInboundMappingsRejectsNonCanonicalPrefixes() {
        String mappingsJson =
            '[{"externalKey":"status","value":"$submission.Status__c","sortOrder":1}]';

        try {
            PublicApiRequestMappingService.validateInboundMappings(
                mappingsJson,
                'PublicApi_Submission__c'
            );
            System.assert(false, 'Expected non-canonical prefixes to be rejected.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(
                e.getMessage().contains('Invalid field reference') ||
                e.getMessage().contains('does not match configured object')
            );
        }
    }

    @IsTest
    static void testValidateInboundMappingsRejectsReadOnlyInboundField() {
        String mappingsJson =
            '[{"externalKey":"submissionNumber","value":"$PublicApi_Submission__c.Name","sortOrder":1}]';

        try {
            PublicApiRequestMappingService.validateInboundMappings(
                mappingsJson,
                'PublicApi_Submission__c'
            );
            System.assert(false, 'Expected read-only inbound fields to be rejected.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('Inbound mapping field is read-only'));
        }
    }

    @IsTest
    static void testValidateInboundMappingsAllowsLiteralValueRows() {
        String mappingsJson =
            '[{"sourceType":"LiteralValue","literalValue":"Manual","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';

        PublicApiRequestMappingService.validateInboundMappings(
            mappingsJson,
            'PublicApi_Submission__c'
        );
    }

    @IsTest
    static void testStructurallyWritableFieldRejectsAutoNumberAndAllowsEditableField() {
        Map<String, Schema.SObjectField> fieldMap = PublicApi_Submission__c.SObjectType.getDescribe().fields.getMap();

        System.assertEquals(
            false,
            PublicApiRequestMappingService.isStructurallyWritableField(fieldMap.get('Name').getDescribe())
        );
        System.assertEquals(
            true,
            PublicApiRequestMappingService.isStructurallyWritableField(fieldMap.get('Status__c').getDescribe())
        );
    }

    @IsTest
    static void testParseMappingsRejectsNonArrayRoot() {
        try {
            PublicApiRequestMappingService.parseMappings('{"x":1}');
            System.assert(false, 'Expected non-array mapping payloads to throw.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(
                e.getMessage().contains('must be a JSON array')
            );
        }
    }

    @IsTest
    static void testParseMappingsDefaultsSourceTypeForLegacyRows() {
        List<PublicApiRequestMappingService.MappingConfig> mappings =
            PublicApiRequestMappingService.parseMappings(
                '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]'
            );

        System.assertEquals(1, mappings.size());
        System.assertEquals('IncomingKey', mappings[0].sourceType);
        System.assertEquals(null, mappings[0].literalValue);
        System.assertEquals(null, mappings[0].defaultValue);
    }

    @IsTest
    static void testGetOutboundFieldApiNamesResolvesKnownFieldsOnly() {
        String mappingsJson =
            '[' +
                '{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1},' +
                '{"externalKey":"created","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":2},' +
                '{"externalKey":"bad","value":"$PublicApi_Submission__c.Does_Not_Exist__c","sortOrder":3}' +
            ']';

        Set<String> fields = PublicApiRequestMappingService.getOutboundFieldApiNames(
            mappingsJson,
            'PublicApi_Submission__c'
        );

        System.assertEquals(true, fields.contains('Status__c'));
        System.assertEquals(true, fields.contains('CreatedDate'));
        System.assertEquals(false, fields.contains('Does_Not_Exist__c'));
    }

    @IsTest
    static void testApplyInboundMappingsSplitsFullNameForConfiguredLeadFields() {
        Lead leadRecord = new Lead(Company = 'Example Co');
        Map<String, Object> payload = new Map<String, Object>{
            'name' => 'Jane Smith',
            'last_name' => ''
        };

        String mappingsJson =
            '[' +
                '{"externalKey":"name","value":"$Lead.FirstName","sortOrder":1},' +
                '{"externalKey":"last_name","value":"$Lead.LastName","sortOrder":2},' +
                '{"externalKey":"company","value":"$Lead.Company","sortOrder":3}' +
            ']';

        PublicApiRequestMappingService.applyInboundMappings(
            leadRecord,
            payload,
            mappingsJson,
            'Lead'
        );

        System.assertEquals('Jane', leadRecord.FirstName);
        System.assertEquals('Smith', leadRecord.LastName);
    }

    private static Account createAccount(String name) {
        Account accountRecord = new Account(Name = name);
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        for (String preferredFieldName : new List<String>{ 'FirstName', 'PersonFirstName' }) {
            if (fieldMap.containsKey(preferredFieldName) &&
                fieldMap.get(preferredFieldName).getDescribe().isCreateable()) {
                accountRecord.put(preferredFieldName, 'Literal');
            }
        }
        for (Schema.SObjectField fieldToken : fieldMap.values()) {
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (describe.isCreateable() &&
                describe.getType() == Schema.DisplayType.String &&
                describe.getName().toLowerCase().contains('last')) {
                accountRecord.put(describe.getName(), name);
            }
        }
        return accountRecord;
    }
}

