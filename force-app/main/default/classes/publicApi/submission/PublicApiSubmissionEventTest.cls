@IsTest
private class PublicApiSubmissionEventTest {
    @IsTest
    static void testSubmissionRequestCreatesConfiguredTargetRecord() {
        String configuredRecordTypeDeveloperName = getConfiguredAccountRecordTypeDeveloperName();
        PublicApi_Integration_Config__c config = new PublicApi_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'submission-event-test-1',
            Target_Object_API_Name__c = 'Account',
            Target_Record_Type_Developer_Name__c = configuredRecordTypeDeveloperName,
            Inbound_Payload_Configuration__c =
                '[{"externalKey":"name","value":"$Account.Name","sortOrder":1}]'
        );
        insert config;

        Test.startTest();
        SObject submission = PublicApiSubmissionService.createSubmissionFromPublicApi(
            '{"name":"Async Submission Account"}',
            'application/json',
            PublicApiConfigService.getConfigById(config.Id)
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        PublicApi_Submission__c auditRecord = [
            SELECT Processing_Status__c,
                   Related_Record_Status__c,
                   Target_Object_API_Name__c,
                   Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE Id = :submission.Id
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_SUCCEEDED, auditRecord.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.RELATED_STATUS_NOT_CONFIGURED, auditRecord.Related_Record_Status__c);
        System.assertEquals('Account', auditRecord.Target_Object_API_Name__c);
        System.assertNotEquals(null, auditRecord.Target_Record_Id__c);

        Account created = [SELECT Id, Name, RecordTypeId FROM Account WHERE Id = :auditRecord.Target_Record_Id__c];
        System.assertEquals('Async Submission Account', created.Name);
        if (!String.isBlank(configuredRecordTypeDeveloperName)) {
            Id expectedRecordTypeId =
                PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, configuredRecordTypeDeveloperName);
            if (expectedRecordTypeId != null) {
                System.assertEquals(expectedRecordTypeId, created.RecordTypeId);
            }
        }
    }

    @IsTest
    static void testSubmissionRequestMarksAuditFailedWhenPayloadCannotBeParsed() {
        String effectiveConfigJson = JSON.serialize(new Map<String, Object>{
            'configId' => null,
            'targetObjectApiName' => 'Task',
            'inboundPayloadConfiguration' =>
                '[{"externalKey":"subject","value":"$Task.Subject","sortOrder":1}]',
            'relatedRecordConfiguration' => null
        });
        PublicApi_Submission__c auditRecord = new PublicApi_Submission__c(
            PublicApi_Integration_Config__c = null,
            Created_By_PublicApi_API__c = true,
            Received_At__c = System.now(),
            Raw_Payload__c = '{invalid json',
            Request_Content_Type__c = 'application/json',
            Target_Object_API_Name__c = 'Task',
            Processing_Status__c = PublicApiSubmissionService.AUDIT_STATUS_RECEIVED,
            Related_Record_Status__c = PublicApiSubmissionService.RELATED_STATUS_PENDING_PROCESSING,
            Effective_Config_JSON__c = effectiveConfigJson
        );
        insert auditRecord;

        Test.startTest();
        PublicApiSubmissionRequestEventService.handleEvents(
            new List<PublicApi_Submission_Request__e>{
                new PublicApi_Submission_Request__e(
                    Submission_Record_Id__c = String.valueOf(auditRecord.Id)
                )
            }
        );
        Test.stopTest();

        PublicApi_Submission__c refreshed = [
            SELECT Processing_Status__c, Processing_Error_Category__c, Processing_Error_Message__c
            FROM PublicApi_Submission__c
            WHERE Id = :auditRecord.Id
        ];
        System.assertEquals(PublicApiSubmissionService.AUDIT_STATUS_FAILED, refreshed.Processing_Status__c);
        System.assertEquals(PublicApiSubmissionService.ERROR_CATEGORY_PAYLOAD, refreshed.Processing_Error_Category__c);
        System.assert(String.isNotBlank(refreshed.Processing_Error_Message__c));
    }

    private static String getConfiguredAccountRecordTypeDeveloperName() {
        Id businessRecordTypeId = PublicApiRecordTypeService.getRecordTypeId(Account.SObjectType, 'Business');
        if (businessRecordTypeId != null) {
            return 'Business';
        }
        return null;
    }
}

