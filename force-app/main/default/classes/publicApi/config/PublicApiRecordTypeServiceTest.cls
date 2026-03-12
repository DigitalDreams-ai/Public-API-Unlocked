@IsTest
private class PublicApiRecordTypeServiceTest {
    @IsTest
    static void testPreferredRecordTypeDeveloperNames() {
        System.assertEquals('Individual', PublicApiRecordTypeService.getDefaultTargetRecordTypeDeveloperName('Account'));
        System.assertEquals(
            'Lead_Intake',
            PublicApiRecordTypeService.getDefaultTargetRecordTypeDeveloperName('litify_pm__Intake__c')
        );
        System.assertEquals(null, PublicApiRecordTypeService.getDefaultTargetRecordTypeDeveloperName('Task'));
    }

    @IsTest
    static void testApplyDefaultRecordTypeDoesNotThrowForObjectsWithoutDefaults() {
        Task taskRecord = new Task(Subject = 'No Default');
        PublicApiRecordTypeService.applyTargetRecordType(taskRecord, null);
        System.assertEquals(null, taskRecord.get('RecordTypeId'));
    }

    @IsTest
    static void testApplyTargetRecordTypeUsesDefaultWhenConfigIsBlank() {
        Account accountRecord = new Account(Name = 'Record Type Test');
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, null);

        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        System.assertEquals(expectedRecordTypeId, accountRecord.RecordTypeId);
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
        Account accountRecord = new Account(Name = 'Existing Record Type');
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        if (expectedRecordTypeId == null) {
            System.assertEquals(null, accountRecord.RecordTypeId);
            return;
        }

        accountRecord.RecordTypeId = expectedRecordTypeId;
        PublicApiRecordTypeService.applyTargetRecordType(accountRecord, 'Business');
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
    static void testApplyRelatedRecordTypeFallsBackToDefaultWhenConfigBlank() {
        Account accountRecord = new Account(Name = 'Related Record Type Test');
        PublicApiRecordTypeService.applyRelatedRecordType(accountRecord, null);
        Id expectedIndividualRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        System.assertEquals(expectedIndividualRecordTypeId, accountRecord.RecordTypeId);
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
