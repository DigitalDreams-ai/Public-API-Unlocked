@IsTest
private class PublicApiRelatedRecordEventServiceTest {
    @IsTest
    static void testPublishAndHandleDeferredAccountRuleForTaskTarget() {
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        String configuredRecordTypeSegment = expectedRecordTypeId == null
            ? ''
            : '"createRecordTypeDeveloperName":"Business",';
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'event-test-key-1',
            Target_Object_API_Name__c = 'Task',
            Inbound_Payload_Configuration__c =
                '[' +
                    '{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}' +
                ']',
            Related_Record_Configuration__c =
                '{' +
                    '"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"email","createIfMissing":true,"onMultipleMatches":"Error",' +
                    configuredRecordTypeSegment +
                    '"createMappings":[{"sourceKey":"phone","fieldName":"Phone"}]' +
                '}'
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
        if (expectedRecordTypeId != null) {
            System.assertEquals(expectedRecordTypeId, related.RecordTypeId);
        }

        PublicApi_Submission__c auditRecord = [
            SELECT Processing_Status__c,
                   Related_Record_Status__c,
                   Target_Object_API_Name__c,
                   Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE Target_Record_Id__c = :String.valueOf(created.Id)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(PublicApiIntakeService.AUDIT_STATUS_SUCCEEDED, auditRecord.Processing_Status__c);
        System.assertEquals('DeferredCompleted', auditRecord.Related_Record_Status__c);
        System.assertEquals('Task', auditRecord.Target_Object_API_Name__c);
        System.assertEquals(String.valueOf(created.Id), auditRecord.Target_Record_Id__c);
    }

    @IsTest
    static void testGetTargetRecordReturnsNullForUnknownTargetObject() {
        System.assertEquals(
            null,
            PublicApiRelatedRecordEventService.getTargetRecord(
                'Does_Not_Exist__c',
                '001000000000000AAA',
                '{"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name","sourceKey":"name"}'
            )
        );
    }

    @IsTest
    static void testHandleEventsMarksDeferredFailuresAsFailedProcessing() {
        Task targetTask = new Task(Subject = 'Deferred Failure Target', Status = 'Not Started', Priority = 'Normal');
        insert targetTask;

        PublicApi_Submission__c auditRecord = new PublicApi_Submission__c(
            Processing_Status__c = PublicApiIntakeService.AUDIT_STATUS_SUCCEEDED,
            Related_Record_Status__c = PublicApiIntakeService.RELATED_STATUS_DEFERRED_PENDING,
            Target_Object_API_Name__c = 'Task',
            Target_Record_Id__c = String.valueOf(targetTask.Id)
        );
        insert auditRecord;

        PublicApi_Related_Record_Request__e requestEvent = new PublicApi_Related_Record_Request__e(
            Audit_Record_Id__c = String.valueOf(auditRecord.Id),
            Target_Record_Id__c = String.valueOf(targetTask.Id),
            Target_Object_API_Name__c = 'Task',
            Payload_JSON__c = '{bad json',
            Related_Record_Configuration_JSON__c =
                '{"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name","sourceKey":"name"}'
        );

        Test.startTest();
        PublicApiRelatedRecordEventService.handleEvents(new List<PublicApi_Related_Record_Request__e>{ requestEvent });
        Test.stopTest();

        PublicApi_Submission__c refreshedAuditRecord = [
            SELECT Processing_Status__c, Related_Record_Status__c, Processing_Error_Category__c, Processing_Error_Message__c
            FROM PublicApi_Submission__c
            WHERE Id = :auditRecord.Id
        ];
        System.assertEquals(PublicApiIntakeService.AUDIT_STATUS_FAILED, refreshedAuditRecord.Processing_Status__c);
        System.assertEquals('DeferredFailed', refreshedAuditRecord.Related_Record_Status__c);
        System.assertEquals('RELATED_RECORD_DEFERRED_ERROR', refreshedAuditRecord.Processing_Error_Category__c);
        System.assert(String.isNotBlank(refreshedAuditRecord.Processing_Error_Message__c));
    }

}
