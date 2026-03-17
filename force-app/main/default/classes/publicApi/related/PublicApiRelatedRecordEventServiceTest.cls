@IsTest
private class PublicApiRelatedRecordEventServiceTest {
    @IsTest
    static void testPublishAndHandleDeferredAccountRuleForTaskTarget() {
        Id expectedRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        String configuredRecordTypeSegment = expectedRecordTypeId == null
            ? ''
            : '"createRecordTypeDeveloperName":"Business",';
        Task createdTask = new Task(Subject = 'Deferred Account Task', Status = 'Not Started', Priority = 'Normal');
        insert createdTask;

        PublicApi_Submission__c auditRecord = new PublicApi_Submission__c(
            Processing_Status__c = PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED,
            Related_Record_Status__c = 'DeferredPending',
            Target_Object_API_Name__c = 'Task',
            Target_Record_Id__c = String.valueOf(createdTask.Id)
        );
        insert auditRecord;
        Id auditRecordId = auditRecord.Id;

        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'Async',
            'lastName' => 'Account',
            'email' => 'async.account@example.com',
            'phone' => '555-0101'
        };

        Test.startTest();
        PublicApiRelatedRecordEventService.handleEvents(
            new List<PublicApi_Related_Record_Request__e>{
                new PublicApi_Related_Record_Request__e(
                    Audit_Record_Id__c = String.valueOf(auditRecord.Id),
                    Target_Record_Id__c = String.valueOf(createdTask.Id),
                    Target_Object_API_Name__c = 'Task',
                    Payload_JSON__c = JSON.serialize(payload),
                    Related_Record_Configuration_JSON__c =
                        '{' +
                            '"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                            '"sourceKey":"email","createIfMissing":true,"onMultipleMatches":"Error",' +
                            configuredRecordTypeSegment +
                            '"createMappings":[{"sourceKey":"phone","fieldName":"Phone"}]' +
                        '}'
                )
            }
        );
        Test.stopTest();

        Task refreshed = [SELECT Id, WhatId FROM Task WHERE Id = :createdTask.Id];
        System.assertNotEquals(null, refreshed.WhatId);

        SObject related = queryAccount(refreshed.WhatId);
        System.assertEquals('Async Account', related.get('Name'));
        System.assertEquals('555-0101', related.get('Phone'));
        if (expectedRecordTypeId != null && accountSupportsRecordTypes()) {
            System.assertEquals(expectedRecordTypeId, related.get('RecordTypeId'));
        }

        PublicApi_Submission__c refreshedAuditRecord = [
            SELECT Processing_Status__c,
                   Related_Record_Status__c,
                   Target_Object_API_Name__c,
                   Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE Id = :auditRecordId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED, refreshedAuditRecord.Processing_Status__c);
        System.assertEquals('DeferredCompleted', refreshedAuditRecord.Related_Record_Status__c);
        System.assertEquals('Task', refreshedAuditRecord.Target_Object_API_Name__c);
        System.assertEquals(String.valueOf(createdTask.Id), refreshedAuditRecord.Target_Record_Id__c);
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
            Processing_Status__c = PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED,
            Related_Record_Status__c = 'DeferredPending',
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
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_FAILED, refreshedAuditRecord.Processing_Status__c);
        System.assertEquals('DeferredFailed', refreshedAuditRecord.Related_Record_Status__c);
        System.assertEquals('RELATED_RECORD_DEFERRED_ERROR', refreshedAuditRecord.Processing_Error_Category__c);
        System.assert(String.isNotBlank(refreshedAuditRecord.Processing_Error_Message__c));
    }

    private static Boolean accountSupportsRecordTypes() {
        return Account.SObjectType.getDescribe().fields.getMap().containsKey('RecordTypeId');
    }

    private static SObject queryAccount(Id accountId) {
        List<String> fieldNames = new List<String>{ 'Id', 'Name', 'Phone' };
        if (accountSupportsRecordTypes()) {
            fieldNames.add('RecordTypeId');
        }
        return Database.query(
            'SELECT ' + String.join(fieldNames, ', ') + ' FROM Account WHERE Id = :accountId'
        );
    }

}

