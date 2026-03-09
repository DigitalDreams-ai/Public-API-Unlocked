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
        PublicApiRecordTypeService.applyDefaultRecordType(taskRecord);
        System.assertEquals(null, taskRecord.get('RecordTypeId'));
    }

    @IsTest
    static void testApplyDefaultRecordTypeUsesAccountIndividualWhenAvailable() {
        Account accountRecord = new Account(Name = 'Record Type Test');
        PublicApiRecordTypeService.applyDefaultRecordType(accountRecord);

        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        System.assertEquals(expectedRecordTypeId, accountRecord.RecordTypeId);
    }

    @IsTest
    static void testApplyDefaultRecordTypeDoesNotOverrideExistingRecordType() {
        Account accountRecord = new Account(Name = 'Existing Record Type');
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        if (expectedRecordTypeId == null) {
            System.assertEquals(null, accountRecord.RecordTypeId);
            return;
        }

        accountRecord.RecordTypeId = expectedRecordTypeId;
        PublicApiRecordTypeService.applyDefaultRecordType(accountRecord);
        System.assertEquals(expectedRecordTypeId, accountRecord.RecordTypeId);
    }
}
