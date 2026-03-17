@IsTest
private class PublicApiRecordTypeServiceTest {
    @IsTest
    static void testApplyTargetRecordTypeDoesNothingWhenConfigIsBlank() {
        Account accountRecord = new Account(Name = 'Record Type Test');
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, null);
        System.assertEquals(null, getRecordTypeIdValue(accountRecord));
    }

    @IsTest
    static void testApplyTargetRecordTypeUsesConfiguredValueWhenAvailable() {
        Id businessRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        Account accountRecord = new Account(Name = 'Configured Record Type');
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, 'Business');

        if (businessRecordTypeId == null || !accountSupportsRecordTypes()) {
            System.assertEquals(null, getRecordTypeIdValue(accountRecord));
            return;
        }

        System.assertEquals(businessRecordTypeId, getRecordTypeIdValue(accountRecord));
    }

    @IsTest
    static void testApplyTargetRecordTypeDoesNotOverrideExistingRecordType() {
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        if (expectedRecordTypeId == null || !accountSupportsRecordTypes()) {
            return;
        }

        Account accountRecord = new Account(Name = 'Existing Record Type');
        accountRecord.put('RecordTypeId', expectedRecordTypeId);
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, 'Individual');
        System.assertEquals(expectedRecordTypeId, getRecordTypeIdValue(accountRecord));
    }

    @IsTest
    static void testApplyRelatedRecordTypeUsesConfiguredValueWhenAvailable() {
        Id businessRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        Account accountRecord = new Account(Name = 'Related Record Type Test');
        PublicApiRecordTypeService.applyRelatedRecordType(accountRecord, 'Business');

        if (businessRecordTypeId == null || !accountSupportsRecordTypes()) {
            System.assertEquals(null, getRecordTypeIdValue(accountRecord));
            return;
        }

        System.assertEquals(businessRecordTypeId, getRecordTypeIdValue(accountRecord));
    }

    @IsTest
    static void testApplyRelatedRecordTypeDoesNothingWhenConfigIsBlank() {
        Account accountRecord = new Account(Name = 'Related Record Type Test');
        PublicApiRecordTypeService.applyRelatedRecordType(accountRecord, null);
        System.assertEquals(null, getRecordTypeIdValue(accountRecord));
    }

    @IsTest
    static void testGetAvailableRecordTypeDeveloperNamesReturnsSortedDeveloperNames() {
        List<String> developerNames = PublicApiRecordTypeService.getAvailableRecordTypeDeveloperNames('Account');
        System.assertNotEquals(null, developerNames);
        System.assertEquals(true, developerNames.size() > 0);
        List<String> sortedDeveloperNames = new List<String>(developerNames);
        sortedDeveloperNames.sort();
        System.assertEquals(sortedDeveloperNames, developerNames);
    }

    private static Boolean accountSupportsRecordTypes() {
        return Account.SObjectType.getDescribe().fields.getMap().containsKey('RecordTypeId');
    }

    private static Id getRecordTypeIdValue(SObject record) {
        return accountSupportsRecordTypes() && record.get('RecordTypeId') != null
            ? (Id) record.get('RecordTypeId')
            : null;
    }
}
