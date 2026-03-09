@IsTest
private class PublicApiRecordTypeServiceTest {
    @IsTest
    static void testPreferredRecordTypeDeveloperNames() {
        System.assertEquals('Individual', PublicApiRecordTypeService.getPreferredRecordTypeDeveloperName('Account'));
        System.assertEquals(
            'Lead_Intake',
            PublicApiRecordTypeService.getPreferredRecordTypeDeveloperName('litify_pm__Intake__c')
        );
        System.assertEquals(null, PublicApiRecordTypeService.getPreferredRecordTypeDeveloperName('Task'));
    }

    @IsTest
    static void testApplyDefaultRecordTypeDoesNotThrowForObjectsWithoutDefaults() {
        Task taskRecord = new Task(Subject = 'No Default');
        PublicApiRecordTypeService.applyDefaultTargetRecordType(taskRecord);
        System.assertEquals(null, taskRecord.get('RecordTypeId'));
    }

    @IsTest
    static void testApplyDefaultTargetRecordTypeUsesAccountIndividualWhenAvailable() {
        Account accountRecord = new Account(Name = 'Record Type Test');
        PublicApiRecordTypeService.applyDefaultTargetRecordType(accountRecord);

        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        System.assertEquals(expectedRecordTypeId, accountRecord.RecordTypeId);
    }

    @IsTest
    static void testApplyDefaultTargetRecordTypeDoesNotOverrideExistingRecordType() {
        Account accountRecord = new Account(Name = 'Existing Record Type');
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        if (expectedRecordTypeId == null) {
            System.assertEquals(null, accountRecord.RecordTypeId);
            return;
        }

        accountRecord.RecordTypeId = expectedRecordTypeId;
        PublicApiRecordTypeService.applyDefaultTargetRecordType(accountRecord);
        System.assertEquals(expectedRecordTypeId, accountRecord.RecordTypeId);
    }

    @IsTest
    static void testApplyDefaultRelatedRecordTypeDoesNotForceAccountRecordType() {
        Account accountRecord = new Account(Name = 'Related Record Type Test');
        PublicApiRecordTypeService.applyDefaultRelatedRecordType(accountRecord);
        Id expectedIndividualRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        System.assertEquals(expectedIndividualRecordTypeId, accountRecord.RecordTypeId);
    }
}
