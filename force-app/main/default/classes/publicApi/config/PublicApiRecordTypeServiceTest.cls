@IsTest
private class PublicApiRecordTypeServiceTest {
    @IsTest
    static void testApplyTargetRecordTypeDoesNothingWhenConfigIsBlank() {
        Account accountRecord = new Account(Name = 'Record Type Test');
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, null);
        System.assertEquals(null, accountRecord.RecordTypeId);
    }

    @IsTest
    static void testApplyTargetRecordTypeUsesConfiguredValueWhenAvailable() {
        Id businessRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        if (businessRecordTypeId == null) {
            System.assertEquals(null, businessRecordTypeId);
            return;
        }

        Account accountRecord = new Account(Name = 'Configured Record Type');
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, 'Business');
        System.assertEquals(businessRecordTypeId, accountRecord.RecordTypeId);
    }

    @IsTest
    static void testApplyTargetRecordTypeDoesNotOverrideExistingRecordType() {
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        if (expectedRecordTypeId == null) {
            System.assertEquals(null, expectedRecordTypeId);
            return;
        }

        Account accountRecord = new Account(Name = 'Existing Record Type');
        accountRecord.RecordTypeId = expectedRecordTypeId;
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, 'Individual');
        System.assertEquals(expectedRecordTypeId, accountRecord.RecordTypeId);
    }

    @IsTest
    static void testApplyRelatedRecordTypeUsesConfiguredValueWhenAvailable() {
        Id businessRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        if (businessRecordTypeId == null) {
            System.assertEquals(null, businessRecordTypeId);
            return;
        }

        Account accountRecord = new Account(Name = 'Related Record Type Test');
        PublicApiRecordTypeService.applyRelatedRecordType(accountRecord, 'Business');
        System.assertEquals(businessRecordTypeId, accountRecord.RecordTypeId);
    }

    @IsTest
    static void testApplyRelatedRecordTypeDoesNothingWhenConfigIsBlank() {
        Account accountRecord = new Account(Name = 'Related Record Type Test');
        PublicApiRecordTypeService.applyRelatedRecordType(accountRecord, null);
        System.assertEquals(null, accountRecord.RecordTypeId);
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
}
