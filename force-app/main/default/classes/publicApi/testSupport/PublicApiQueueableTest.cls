@IsTest
private class PublicApiQueueableTest {
    @IsTest
    static void testSubmissionQueueableProcessesSubmissionAndBatchHelpers() {
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'queueable-submission-test',
            Target_Object_API_Name__c = 'Account',
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"name","value":"$Account.Name","sortOrder":1}]'
        );
        insert config;

        String effectiveConfigJson = JSON.serialize(new Map<String, Object>{
            'configId' => config.Id,
            'targetObjectApiName' => 'Account',
            'targetRecordTypeDeveloperName' => null,
            'inboundPayloadConfiguration' =>
                '[{"externalKey":"name","value":"$Account.Name","sortOrder":1}]',
            'relatedRecordConfiguration' => null
        });
        PublicApi_Submission__c auditRecord = new PublicApi_Submission__c(
            PublicApi_Integration_Config__c = config.Id,
            Created_By_PublicApi_API__c = true,
            Received_At__c = System.now(),
            Raw_Payload__c = '{"name":"Queueable Account"}',
            Request_Content_Type__c = 'application/json',
            Target_Object_API_Name__c = 'Account',
            Processing_Status__c = PublicApiSubmissionService.AUDIT_STATUS_RECEIVED,
            Related_Record_Status__c = PublicApiSubmissionService.RELATED_STATUS_PENDING_PROCESSING,
            Effective_Config_JSON__c = effectiveConfigJson
        );
        insert auditRecord;

        List<Task> batchTasks = new List<Task>();
        for (Integer index = 0; index < 95; index++) {
            batchTasks.add(new Task(
                Subject = 'Queueable Batch ' + index,
                Status = 'Not Started',
                Priority = 'Normal'
            ));
        }
        insert batchTasks;

        List<Id> taskIds = new List<Id>();
        taskIds.add(null);
        for (Task taskRecord : batchTasks) {
            taskIds.add(taskRecord.Id);
        }

        List<Id> firstBatch = PublicApiSubmissionRequestQueueable.takeBatch(taskIds);
        List<Id> remainder = PublicApiSubmissionRequestQueueable.dropBatch(taskIds);
        System.assertEquals(PublicApiSubmissionRequestQueueable.MAX_SUBMISSIONS_PER_JOB - 1, firstBatch.size());
        System.assertEquals(6, remainder.size());
        System.assertEquals(0, PublicApiSubmissionRequestQueueable.takeBatch(null).size());
        System.assertEquals(0, PublicApiSubmissionRequestQueueable.dropBatch(null).size());

        Test.startTest();
        PublicApiSubmissionRequestQueueable.enqueue(new List<Id>{ auditRecord.Id });
        PublicApiSubmissionRequestQueueable.enqueue(null);
        Test.stopTest();

        PublicApi_Submission__c refreshedAuditRecord = [
            SELECT Processing_Status__c, Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE Id = :auditRecord.Id
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED, refreshedAuditRecord.Processing_Status__c);
        System.assertNotEquals(null, refreshedAuditRecord.Target_Record_Id__c);

        Account createdAccount = [
            SELECT Name
            FROM Account
            WHERE Id = :refreshedAuditRecord.Target_Record_Id__c
        ];
        System.assertEquals('Queueable Account', createdAccount.Name);
    }

    @IsTest
    static void testRelatedRecordQueueableProcessesRequestsAndHelpers() {
        Task createdTask = new Task(Subject = 'Queueable Related Task', Status = 'Not Started', Priority = 'Normal');
        insert createdTask;

        PublicApi_Submission__c auditRecord = new PublicApi_Submission__c(
            Processing_Status__c = PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED,
            Related_Record_Status__c = 'DeferredPending',
            Target_Object_API_Name__c = 'Task',
            Target_Record_Id__c = String.valueOf(createdTask.Id)
        );
        insert auditRecord;

        PublicApiRelatedRecordQueueable.RequestItem requestItem =
            new PublicApiRelatedRecordQueueable.RequestItem(
                null,
                auditRecord.Id,
                createdTask.Id,
                'Task',
                JSON.serialize(new Map<String, Object>{
                    'email' => 'queueable.related@example.com',
                    'phone' => '555-1212'
                }),
                '{' +
                    '"targetLookupField":"WhatId","relatedObjectApiName":"Account","matchFieldName":"Name",' +
                    '"sourceKey":"email","createIfMissing":true,"onMultipleMatches":"Error",' +
                    '"createMappings":[{"sourceKey":"phone","fieldName":"Phone"}]' +
                '}'
            );

        List<String> serializedItems = new List<String>();
        serializedItems.add(JSON.serialize(requestItem));
        serializedItems.add('');
        serializedItems.add('{bad json');
        for (Integer index = 0; index < 94; index++) {
            serializedItems.add(JSON.serialize(requestItem));
        }

        List<PublicApiRelatedRecordQueueable.RequestItem> deserializedItems =
            PublicApiRelatedRecordQueueable.deserializeItems(serializedItems);
        System.assertEquals(95, deserializedItems.size());
        System.assertEquals(90, PublicApiRelatedRecordQueueable.takeBatch(serializedItems).size());
        System.assertEquals(7, PublicApiRelatedRecordQueueable.dropBatch(serializedItems).size());
        System.assertEquals(0, PublicApiRelatedRecordQueueable.deserializeItems(null).size());
        System.assertEquals(0, PublicApiRelatedRecordQueueable.takeBatch(null).size());
        System.assertEquals(0, PublicApiRelatedRecordQueueable.dropBatch(null).size());

        Test.startTest();
        PublicApiRelatedRecordQueueable.enqueue(new List<PublicApiRelatedRecordQueueable.RequestItem>{ requestItem });
        PublicApiRelatedRecordQueueable.enqueue(null);
        Test.stopTest();

        Task refreshedTask = [SELECT WhatId FROM Task WHERE Id = :createdTask.Id];
        System.assertNotEquals(null, refreshedTask.WhatId);

        Account relatedAccount = [
            SELECT Name, Phone
            FROM Account
            WHERE Id = :refreshedTask.WhatId
        ];
        System.assertEquals('queueable.related@example.com', relatedAccount.Name);
        System.assertEquals('555-1212', relatedAccount.Phone);

        PublicApi_Submission__c refreshedAuditRecord = [
            SELECT Processing_Status__c, Related_Record_Status__c
            FROM PublicApi_Submission__c
            WHERE Id = :auditRecord.Id
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED, refreshedAuditRecord.Processing_Status__c);
        System.assertEquals('DeferredCompleted', refreshedAuditRecord.Related_Record_Status__c);
    }
}
