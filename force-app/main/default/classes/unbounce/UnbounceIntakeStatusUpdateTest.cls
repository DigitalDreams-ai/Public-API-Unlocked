@IsTest
private class UnbounceIntakeStatusUpdateTest {
    private static final String TEST_API_KEY = 'status-test-key';
    private static List<HttpRequest> capturedRequests = new List<HttpRequest>();

    private class StatusUpdateCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            capturedRequests.add(request);
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('ok');
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        insert new Unbounce_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = TEST_API_KEY,
            Status_Update_Webhook_URL__c = 'https://example.com/unbounce/status',
            Status_Update_Webhook_Secret__c = 'status-secret'
        );
    }

    @IsTest
    static void testStatusChange_SendsWebhook() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());
        litify_pm__Intake__c intake = createUnbounceIntake();
        String nextStatus = getAlternateStatusValue(intake.litify_pm__Status__c);

        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        System.assertEquals(1, capturedRequests.size());
        HttpRequest request = capturedRequests[0];
        System.assertEquals('POST', request.getMethod());
        System.assertEquals('https://example.com/unbounce/status', request.getEndpoint());
        System.assertEquals('status_changed', request.getHeader('X-Unbounce-Event-Type'));
        System.assertEquals(
            UnbounceClient.generateWebhookSignature(request.getBody(), 'status-secret'),
            request.getHeader('x-unbounce-signature')
        );

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
        System.assertEquals('status_changed', payload.get('eventType'));
        System.assertEquals(String.valueOf(intake.Id), payload.get('intakeId'));
        System.assertEquals('Lead Generated', payload.get('previousStatus'));
        System.assertEquals(nextStatus, payload.get('status'));
        System.assertEquals('Status', payload.get('firstName'));
        System.assertEquals('Webhook', payload.get('lastName'));
        System.assertEquals('status.webhook@example.com', payload.get('email'));
    }

    @IsTest
    static void testStatusChange_DoesNotSendForNonUnbounceIntake() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());
        litify_pm__Intake__c intake = createUnbounceIntake();
        String nextStatus = getAlternateStatusValue(intake.litify_pm__Status__c);

        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            Created_By_Unbounce_API__c = false,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        System.assertEquals(0, capturedRequests.size());
    }

    @IsTest
    static void testStatusChange_DoesNotSendWhenStatusIsUnchanged() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());
        litify_pm__Intake__c intake = createUnbounceIntake();

        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Description__c = 'Updated description'
        );
        Test.stopTest();

        System.assertEquals(0, capturedRequests.size());
    }

    private static litify_pm__Intake__c createUnbounceIntake() {
        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Status',
            'last_name' => 'Webhook',
            'email' => 'status.webhook@example.com',
            'phone' => '555-222-4444',
            'description' => 'Track status changes',
            'caseType' => 'Auto Accident'
        };

        litify_pm__Intake__c created = UnbounceIntakeService.createIntakeFromUnbounce(
            payload,
            UnbounceConfigService.getConfigForApiKey(TEST_API_KEY)
        );
        return [
            SELECT Id,
                   Name,
                   litify_pm__Status__c,
                   Created_By_Unbounce_API__c,
                   Unbounce_Integration_Config_Id__c
            FROM litify_pm__Intake__c
            WHERE Id = :created.Id
        ];
    }

    private static String getAlternateStatusValue(String currentStatus) {
        for (Schema.PicklistEntry entry :
            litify_pm__Intake__c.litify_pm__Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() != currentStatus) {
                return entry.getValue();
            }
        }
        System.assert(false, 'Expected at least one alternate active Intake status value');
        return null;
    }

    private static void resetCapturedRequests() {
        capturedRequests.clear();
    }
}
