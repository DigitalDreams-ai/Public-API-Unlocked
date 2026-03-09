@IsTest
private class PublicApiRelatedRecordEventServiceTest {
    @IsTest
    static void testPublishAndHandleDeferredAccountRuleForTaskTarget() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'event-test-key-1',
            Target_Object_API_Name__c = 'Task',
            Inbound_Payload_Configuration__c =
                '[' +
                    '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}' +
                ']',
            Related_Record_Configuration__c =
                '[' +
                    '{"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"email","createIfMissing":true,"onMultipleMatches":"Error",' +
                    '"createMappings":[{"sourceKey":"phone","fieldName":"Phone"}]}' +
                ']'
        );
        insert config;

        Map<String, Object> payload = new Map<String, Object>{
            'subject' => 'Deferred Account Task',
            'firstName' => 'Async',
            'lastName' => 'Account',
            'email' => 'async.account@example.com',
            'phone' => '555-0101'
        };

        Test.startTest();
        SObject created = PublicApiIntakeService.createIntakeFromPublicApi(
            payload,
            PublicApiConfigService.getConfigById(config.Id)
        );
        Test.stopTest();

        Task refreshed = [SELECT Id, WhatId FROM Task WHERE Id = :created.Id];
        System.assertNotEquals(null, refreshed.WhatId);

        Account related = [SELECT Id, Name, Phone, RecordTypeId FROM Account WHERE Id = :refreshed.WhatId];
        System.assertEquals('Async Account', related.Name);
        System.assertEquals('555-0101', related.Phone);
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Individual');
        if (expectedRecordTypeId != null) {
            System.assertEquals(expectedRecordTypeId, related.RecordTypeId);
        }
    }

    @IsTest
    static void testGetTargetRecordReturnsNullForUnknownTargetObject() {
        System.assertEquals(
            null,
            PublicApiRelatedRecordEventService.getTargetRecord(
                'Does_Not_Exist__c',
                '001000000000000AAA',
                '[{"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name","sourceKey":"name"}]'
            )
        );
    }
}
