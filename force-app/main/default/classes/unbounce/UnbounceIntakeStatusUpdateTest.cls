@IsTest(IsParallel=false)
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
            Outbound_Webhook_URL__c = 'https://example.com/unbounce/status',
            Outbound_Webhook_Secret__c = 'status-secret'
        );
    }

    @IsTest
    static void testStatusChange_SendsWebhook() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());
        litify_pm__Intake__c intake = createUnbounceIntake();
        String nextStatus = getRequiredStatusValue('Referred Out');

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
            request.getHeader(UnbounceIntakeStatusUpdateQueueable.DEFAULT_SIGNATURE_HEADER)
        );

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
        System.assertEquals('Status', payload.get('firstName'));
        System.assertEquals('Webhook', payload.get('lastName'));
        System.assertEquals(intake.litify_pm__Email__c, payload.get('email'));
        System.assertEquals('test-gclid', payload.get('gclid'));

        List<Unbounce_Webhook_Delivery__c> deliveries = [
            SELECT Intake__c,
                   Triggered_Status__c,
                   Status__c,
                   Status_Code__c,
                   Request_JSON__c,
                   Response_JSON__c,
                   Unbounce_Integration_Config__c
            FROM Unbounce_Webhook_Delivery__c
            WHERE Intake__c = :intake.Id
        ];
        System.assertEquals(1, deliveries.size());
        System.assertEquals('Referred Out', deliveries[0].Triggered_Status__c);
        System.assertEquals('Success', deliveries[0].Status__c);
        System.assertEquals(200, deliveries[0].Status_Code__c);
        System.assert(deliveries[0].Request_JSON__c.contains('"gclid":"test-gclid"'));
        System.assert(deliveries[0].Response_JSON__c.contains('"statusCode":200'));

        Unbounce_Integration_Config__c config = [
            SELECT Last_Webhook_Delivery_Attempt__c,
                   Last_Webhook_Delivery_Status__c,
                   Last_Webhook_Request_JSON__c,
                   Last_Webhook_Response_JSON__c
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = :TEST_API_KEY
            LIMIT 1
        ];
        System.assertEquals('Success', config.Last_Webhook_Delivery_Status__c);
        System.assertNotEquals(null, config.Last_Webhook_Delivery_Attempt__c);
        System.assert(config.Last_Webhook_Request_JSON__c.contains('"email"'));
        System.assert(config.Last_Webhook_Response_JSON__c.contains('"statusCode":200'));

        litify_pm__Intake__c refreshed = [
            SELECT Google_Ads_Conversion_Event__c,
                   Google_Ads_Conversion_Time__c
            FROM litify_pm__Intake__c
            WHERE Id = :intake.Id
        ];
        System.assertEquals(formatAsIso8601(refreshed.Google_Ads_Conversion_Time__c), payload.get('conversionTime'));
        System.assertEquals(6, payload.size());
        System.assert(payload.containsKey('createdDate'));
        System.assert(payload.containsKey('conversionTime'));
        System.assertEquals(false, payload.containsKey('status'));
        System.assertEquals(false, payload.containsKey('previousStatus'));
        System.assertEquals(false, payload.containsKey('phone'));
        System.assertEquals('Referred Out', refreshed.Google_Ads_Conversion_Event__c);
        System.assertNotEquals(null, refreshed.Google_Ads_Conversion_Time__c);
    }

    @IsTest
    static void testBuildPayload_ContainsOnlyRequestedFields() {
        litify_pm__Intake__c intake = createUnbounceIntake();
        UnbounceIntakeStatusUpdateQueueable.DeliveryItem item =
            new UnbounceIntakeStatusUpdateQueueable.DeliveryItem(
                intake.Id,
                createSyntheticConfigId(),
                'Lead Generated',
                'Qualified',
                System.now()
            );

        Map<String, Object> payload = UnbounceIntakeStatusUpdateQueueable.buildPayload(intake, item);

        System.assertEquals('Status', payload.get('firstName'));
        System.assertEquals('Webhook', payload.get('lastName'));
        System.assertEquals(intake.litify_pm__Email__c, payload.get('email'));
        System.assertEquals(intake.GCLID__c, payload.get('gclid'));
        System.assertEquals(formatAsIso8601(intake.Google_Ads_Conversion_Time__c), payload.get('conversionTime'));
        System.assertEquals(6, payload.size());
        System.assert(payload.containsKey('createdDate'));
        System.assert(payload.containsKey('conversionTime'));
        System.assertEquals(false, payload.containsKey('status'));
    }

    @IsTest
    static void testStatusChange_AppliesConfiguredAuthAndCustomHeaders() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());

        Unbounce_Integration_Config__c config = [
            SELECT Id,
                   Outbound_Webhook_Secret__c
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = :TEST_API_KEY
            LIMIT 1
        ];
        config.Outbound_Webhook_Secret__c = null;
        config.Outbound_Auth_Mode__c = 'BearerToken';
        config.Outbound_Header_Value__c = 'status-bearer-token';
        config.Outbound_Header_Name__c = null;
        config.Outbound_Content_Type__c = 'application/json; charset=UTF-8';
        config.Outbound_Additional_Headers_JSON__c =
            '{"Content-Type":"application/json; charset=UTF-8","X-Unbounce-Event-Type":"status_changed","Authorization":"Bearer status-bearer-token","X-Correlation-Source":"Unbounce","X-Environment":"Test"}';
        update config;

        litify_pm__Intake__c intake = createUnbounceIntake();
        String nextStatus = getRequiredStatusValue('Converted');
        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        System.assertEquals(1, capturedRequests.size());
        HttpRequest request = capturedRequests[0];
        System.assertEquals('application/json; charset=UTF-8', request.getHeader('Content-Type'));
        System.assertEquals('Bearer status-bearer-token', request.getHeader('Authorization'));
        System.assertEquals('Unbounce', request.getHeader('X-Correlation-Source'));
        System.assertEquals('Test', request.getHeader('X-Environment'));
        System.assertEquals(null, request.getHeader(UnbounceIntakeStatusUpdateQueueable.DEFAULT_SIGNATURE_HEADER));
    }

    @IsTest
    static void testApplyAdditionalHeaders_IgnoresManagedHeadersStoredInPreviewJson() {
        HttpRequest request = new HttpRequest();
        UnbounceConfigService.Config config = new UnbounceConfigService.Config();
        config.outboundAuthMode = 'BearerToken';
        config.outboundHeaderValue = 'status-bearer-token';
        config.outboundContentType = 'application/json; charset=UTF-8';
        config.outboundAdditionalHeadersJson =
            '{"Content-Type":"application/json; charset=UTF-8","X-Unbounce-Event-Type":"status_changed","Authorization":"Bearer status-bearer-token","X-Correlation-Source":"Unbounce"}';

        UnbounceIntakeStatusUpdateQueueable.applyRequestConfiguration(request, config, '{"ok":true}');

        System.assertEquals('application/json; charset=UTF-8', request.getHeader('Content-Type'));
        System.assertEquals('status_changed', request.getHeader('X-Unbounce-Event-Type'));
        System.assertEquals('Bearer status-bearer-token', request.getHeader('Authorization'));
        System.assertEquals('Unbounce', request.getHeader('X-Correlation-Source'));
    }

    @IsTest
    static void testStatusChange_AppliesConfiguredPayloadTemplate() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());

        Unbounce_Integration_Config__c config = [
            SELECT Id
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = :TEST_API_KEY
            LIMIT 1
        ];
        config.Outbound_Payload_Configuration__c =
            '{"lead":{"first_name":"$.firstName","email":"$.email","gclid":"$.gclid"},"created_at":"$.createdDate","event":"status_changed"}';
        update config;

        litify_pm__Intake__c intake = createUnbounceIntake();
        String nextStatus = getRequiredStatusValue('Referred Out');
        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        System.assertEquals(1, capturedRequests.size());
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(capturedRequests[0].getBody());
        Map<String, Object> lead = (Map<String, Object>) payload.get('lead');
        System.assertEquals('Status', lead.get('first_name'));
        System.assertEquals(intake.litify_pm__Email__c, lead.get('email'));
        System.assertEquals('test-gclid', lead.get('gclid'));
        System.assertEquals('status_changed', payload.get('event'));
        System.assert(payload.containsKey('created_at'));
        System.assertEquals(false, payload.containsKey('firstName'));
    }

    @IsTest
    static void testApplyRequestConfiguration_UsesApiKeyHeaderAndArrayConfiguredHeaders() {
        HttpRequest request = new HttpRequest();
        UnbounceConfigService.Config config = new UnbounceConfigService.Config();
        config.outboundAuthMode = 'ApiKeyHeader';
        config.outboundHeaderName = 'X-Partner-Key';
        config.outboundHeaderValue = 'partner-token';
        config.outboundAdditionalHeadersJson =
            '[{"name":"X-One","value":"1"},{"header":"X-Two","value":"2"}]';

        UnbounceIntakeStatusUpdateQueueable.applyRequestConfiguration(request, config, '{"ok":true}');

        System.assertEquals('application/json', request.getHeader('Content-Type'));
        System.assertEquals('status_changed', request.getHeader('X-Unbounce-Event-Type'));
        System.assertEquals('partner-token', request.getHeader('X-Partner-Key'));
        System.assertEquals('1', request.getHeader('X-One'));
        System.assertEquals('2', request.getHeader('X-Two'));
    }

    @IsTest
    static void testApplyAuthHeaders_UsesBasicAndHmacModes() {
        HttpRequest basicRequest = new HttpRequest();
        UnbounceConfigService.Config basicConfig = new UnbounceConfigService.Config();
        basicConfig.outboundAuthMode = 'BasicAuth';
        basicConfig.outboundHeaderValue = 'user:pass';

        UnbounceIntakeStatusUpdateQueueable.applyAuthHeaders(basicRequest, basicConfig, '{"ok":true}');

        System.assertEquals(
            'Basic ' + EncodingUtil.base64Encode(Blob.valueOf('user:pass')),
            basicRequest.getHeader('Authorization')
        );

        HttpRequest signatureRequest = new HttpRequest();
        UnbounceConfigService.Config signatureConfig = new UnbounceConfigService.Config();
        signatureConfig.outboundAuthMode = 'HmacSignature';
        signatureConfig.outboundHeaderName = 'X-Custom-Signature';
        signatureConfig.statusUpdateWebhookSecret = 'secret-value';
        String payload = '{"hello":"world"}';

        UnbounceIntakeStatusUpdateQueueable.applyAuthHeaders(signatureRequest, signatureConfig, payload);

        System.assertEquals(
            UnbounceClient.generateWebhookSignature(payload, 'secret-value'),
            signatureRequest.getHeader('X-Custom-Signature')
        );
    }

    @IsTest
    static void testApplyPayloadConfiguration_UsesConfiguredTemplate() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'Jane',
            'lastName' => 'Smith',
            'email' => 'jane@example.com',
            'gclid' => 'gclid-123',
            'createdDate' => '2026-03-03T00:00:00.000Z'
        };
        UnbounceConfigService.Config config = new UnbounceConfigService.Config();
        config.outboundPayloadConfiguration =
            '{"lead":{"first_name":"$.firstName","email":"$.email"},"gclid":"$.gclid"}';

        Map<String, Object> transformed =
            UnbounceIntakeStatusUpdateQueueable.applyPayloadConfiguration(payload, config);

        Map<String, Object> lead = (Map<String, Object>) transformed.get('lead');
        System.assertEquals('Jane', lead.get('first_name'));
        System.assertEquals('jane@example.com', lead.get('email'));
        System.assertEquals('gclid-123', transformed.get('gclid'));
        System.assertEquals(false, transformed.containsKey('firstName'));
    }

    @IsTest
    static void testQueueableBatching_SplitsOversizedWork() {
        List<String> serializedItems = new List<String>();
        Integer totalItems = UnbounceIntakeStatusUpdateQueueable.MAX_DELIVERIES_PER_JOB + 7;
        for (Integer index = 0; index < totalItems; index++) {
            serializedItems.add('item-' + index);
        }

        List<String> batch = UnbounceIntakeStatusUpdateQueueable.takeBatch(serializedItems);
        List<String> remaining = UnbounceIntakeStatusUpdateQueueable.dropBatch(serializedItems);

        System.assertEquals(
            UnbounceIntakeStatusUpdateQueueable.MAX_DELIVERIES_PER_JOB,
            batch.size()
        );
        System.assertEquals(totalItems - batch.size(), remaining.size());
        System.assertEquals('item-0', batch[0]);
        System.assertEquals(
            'item-' + String.valueOf(UnbounceIntakeStatusUpdateQueueable.MAX_DELIVERIES_PER_JOB),
            remaining[0]
        );
    }

    @IsTest
    static void testStatusChange_DoesNotSendForNonUnbounceIntake() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());
        litify_pm__Intake__c intake = new litify_pm__Intake__c(
            litify_pm__First_Name__c = 'Not',
            litify_pm__Last_Name__c = 'Tracked',
            litify_pm__Email__c = 'not.tracked@example.com',
            litify_pm__Status__c = 'Lead Generated'
        );
        insert intake;
        String nextStatus = getRequiredStatusValue('Referred Out');

        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        System.assertEquals(0, capturedRequests.size());
        System.assertEquals(0, [SELECT Count() FROM Unbounce_Webhook_Delivery__c WHERE Intake__c = :intake.Id]);
        litify_pm__Intake__c refreshed = [
            SELECT Google_Ads_Conversion_Event__c,
                   Google_Ads_Conversion_Time__c
            FROM litify_pm__Intake__c
            WHERE Id = :intake.Id
        ];
        System.assertEquals(null, refreshed.Google_Ads_Conversion_Event__c);
        System.assertEquals(null, refreshed.Google_Ads_Conversion_Time__c);
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

    @IsTest
    static void testStatusChange_DoesNotSendWithoutTrackingEvenIfFieldsLookSimilar() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());

        Account referredByParty = createReferredByParty('PMAX-Unbounce');
        Unbounce_Integration_Config__c config = [
            SELECT Id, Referred_By_Party_Name__c
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = :TEST_API_KEY
            LIMIT 1
        ];
        config.Referred_By_Party_Name__c = referredByParty.Name;
        update config;

        String advertisingSourceTypeValue = getAdvertisingSourceTypeValue();
        litify_pm__Intake__c intake = new litify_pm__Intake__c(
            litify_pm__First_Name__c = 'Legacy',
            litify_pm__Last_Name__c = 'Unbounce',
            litify_pm__Email__c = 'legacy.unbounce@example.com',
            litify_pm__Phone__c = '555-333-5555',
            litify_pm__Status__c = 'Lead Generated',
            litify_pm__lit_Exact_Source__c = 'https://shtest.ubpages.com/sh_test/'
        );
        setOptionalIntakeField(intake, 'Referred_By__c', referredByParty.Id);
        if (String.isNotBlank(advertisingSourceTypeValue)) {
            intake.litify_pm__Source_Type__c = advertisingSourceTypeValue;
        }
        insert intake;

        String nextStatus = getRequiredStatusValue('Referred Out');
        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        System.assertEquals(0, capturedRequests.size());
    }

    @IsTest
    static void testStatusChange_DoesNotSendForDisallowedStatus() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());
        litify_pm__Intake__c intake = createUnbounceIntake();
        String nextStatus = getDisallowedStatusValue(intake.litify_pm__Status__c);

        resetCapturedRequests();

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        System.assertEquals(0, capturedRequests.size());
    }

    @IsTest
    static void testStatusChange_SendsForConverted() {
        System.assertEquals(true, UnbounceIntakeStatusUpdateTriggerHandler.shouldSendStatusUpdate('Converted'));
        System.assertEquals(true, UnbounceIntakeStatusUpdateTriggerHandler.shouldSendStatusUpdate('Referred Out'));
        System.assertEquals(false, UnbounceIntakeStatusUpdateTriggerHandler.shouldSendStatusUpdate('Lead Generated'));
    }

    @IsTest
    static void testStatusChange_StampsGoogleAdsConversionFieldsForConverted() {
        litify_pm__Intake__c intake = createUnbounceIntake();
        String nextStatus = getRequiredStatusValue('Converted');

        Test.startTest();
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__Status__c = nextStatus
        );
        Test.stopTest();

        litify_pm__Intake__c refreshed = [
            SELECT Google_Ads_Conversion_Event__c,
                   Google_Ads_Conversion_Time__c
            FROM litify_pm__Intake__c
            WHERE Id = :intake.Id
        ];
        System.assertEquals('Converted', refreshed.Google_Ads_Conversion_Event__c);
        System.assertNotEquals(null, refreshed.Google_Ads_Conversion_Time__c);
    }

    @IsTest
    static void testStatusChange_MalformedPayloadTemplateFailsOneDeliveryWithoutAbortingBatch() {
        resetCapturedRequests();
        Test.setMock(HttpCalloutMock.class, new StatusUpdateCalloutMock());

        Unbounce_Integration_Config__c badConfig = [
            SELECT Id, Outbound_Payload_Configuration__c
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = :TEST_API_KEY
            LIMIT 1
        ];
        badConfig.Outbound_Payload_Configuration__c = '{"lead":';
        update badConfig;

        Unbounce_Integration_Config__c goodConfig = new Unbounce_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = 'status-test-key-good',
            Outbound_Webhook_URL__c = 'https://example.com/unbounce/status/good',
            Outbound_Webhook_Secret__c = 'status-secret-good'
        );
        insert goodConfig;

        litify_pm__Intake__c badIntake = createTrackedIntakeForConfig(
            badConfig.Id,
            'Bad',
            'Payload',
            'bad.payload@example.com'
        );
        litify_pm__Intake__c goodIntake = createTrackedIntakeForConfig(
            goodConfig.Id,
            'Good',
            'Payload',
            'good.payload@example.com'
        );

        String nextStatus = getRequiredStatusValue('Converted');
        resetCapturedRequests();

        Test.startTest();
        update new List<litify_pm__Intake__c>{
            new litify_pm__Intake__c(Id = badIntake.Id, litify_pm__Status__c = nextStatus),
            new litify_pm__Intake__c(Id = goodIntake.Id, litify_pm__Status__c = nextStatus)
        };
        Test.stopTest();

        System.assertEquals(1, capturedRequests.size());
        System.assert(capturedRequests[0].getBody().contains('good.payload@example.com'));

        Map<Id, Unbounce_Webhook_Delivery__c> deliveriesByIntake = new Map<Id, Unbounce_Webhook_Delivery__c>();
        for (Unbounce_Webhook_Delivery__c delivery : [
            SELECT Intake__c,
                   Status__c,
                   Request_JSON__c,
                   Response_JSON__c
            FROM Unbounce_Webhook_Delivery__c
            WHERE Intake__c IN :new Set<Id>{ badIntake.Id, goodIntake.Id }
        ]) {
            deliveriesByIntake.put(delivery.Intake__c, delivery);
        }
        System.assertEquals(2, deliveriesByIntake.size());
        System.assertEquals('Failed', deliveriesByIntake.get(badIntake.Id).Status__c);
        System.assert(deliveriesByIntake.get(badIntake.Id).Response_JSON__c.contains('"exceptionMessage"'));
        System.assertEquals('Success', deliveriesByIntake.get(goodIntake.Id).Status__c);
    }

    @IsTest
    static void testPersistDeliveryResults_UsesBulkDmlStatements() {
        Unbounce_Integration_Config__c config = [
            SELECT Id
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = :TEST_API_KEY
            LIMIT 1
        ];
        litify_pm__Intake__c firstIntake = new litify_pm__Intake__c(
            litify_pm__First_Name__c = 'Bulk',
            litify_pm__Last_Name__c = 'One',
            litify_pm__Email__c = 'bulk.one@example.com',
            litify_pm__Status__c = 'Lead Generated'
        );
        litify_pm__Intake__c secondIntake = new litify_pm__Intake__c(
            litify_pm__First_Name__c = 'Bulk',
            litify_pm__Last_Name__c = 'Two',
            litify_pm__Email__c = 'bulk.two@example.com',
            litify_pm__Status__c = 'Lead Generated'
        );
        insert new List<litify_pm__Intake__c>{ firstIntake, secondIntake };

        UnbounceWebhookDeliveryRecordService.DeliveryResult successResult =
            UnbounceIntakeStatusUpdateQueueable.buildDeliveryResult(true, 200, 'ok', 'OK');
        Unbounce_Webhook_Delivery__c firstDelivery = UnbounceWebhookDeliveryRecordService.buildDeliveryRecord(
            config.Id,
            firstIntake.Id,
            'Converted',
            'https://example.com/one',
            '{"first":1}',
            successResult
        );
        Unbounce_Webhook_Delivery__c secondDelivery = UnbounceWebhookDeliveryRecordService.buildDeliveryRecord(
            config.Id,
            secondIntake.Id,
            'Referred Out',
            'https://example.com/two',
            '{"second":2}',
            successResult
        );
        Map<Id, Unbounce_Integration_Config__c> summaryUpdatesByConfig =
            new Map<Id, Unbounce_Integration_Config__c>();
        UnbounceWebhookDeliveryRecordService.mergeLatestDeliverySummary(summaryUpdatesByConfig, firstDelivery);
        UnbounceWebhookDeliveryRecordService.mergeLatestDeliverySummary(summaryUpdatesByConfig, secondDelivery);

        Integer dmlStatementsBefore = Limits.getDmlStatements();
        UnbounceWebhookDeliveryRecordService.persistDeliveryResults(
            new List<Unbounce_Webhook_Delivery__c>{ firstDelivery, secondDelivery },
            summaryUpdatesByConfig
        );
        Integer dmlStatementsUsed = Limits.getDmlStatements() - dmlStatementsBefore;

        System.assertEquals(2, dmlStatementsUsed);
    }

    private static litify_pm__Intake__c createUnbounceIntake() {
        Unbounce_Integration_Config__c config = [
            SELECT Id
            FROM Unbounce_Integration_Config__c
            WHERE API_Key__c = :TEST_API_KEY
            LIMIT 1
        ];
        String uniqueEmail =
            'status.webhook+' + String.valueOf(Crypto.getRandomLong()).replace('-', '0') + '@example.com';
        litify_pm__Intake__c created = createTrackedIntakeForConfig(
            config.Id,
            'Status',
            'Webhook',
            uniqueEmail
        );
        List<Unbounce_Intake_Tracking__c> tracking = [
            SELECT Id, Intake_Id__c, Unbounce_Integration_Config__c
            FROM Unbounce_Intake_Tracking__c
            WHERE Intake_Id__c = :String.valueOf(created.Id)
        ];
        System.assertEquals(1, tracking.size());

        return [
            SELECT Id,
                   CreatedDate,
                   Google_Ads_Conversion_Event__c,
                   Google_Ads_Conversion_Time__c,
                   litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Status__c,
                   litify_pm__Email__c,
                   GCLID__c
            FROM litify_pm__Intake__c
            WHERE Id = :created.Id
        ];
    }

    private static litify_pm__Intake__c createTrackedIntakeForConfig(
        Id configId,
        String firstName,
        String lastName,
        String email
    ) {
        litify_pm__Intake__c intake = new litify_pm__Intake__c(
            litify_pm__First_Name__c = firstName,
            litify_pm__Last_Name__c = lastName,
            litify_pm__Email__c = email,
            litify_pm__Status__c = 'Lead Generated',
            GCLID__c = firstName == 'Status' ? 'test-gclid' : 'tracked-gclid',
            Created_By_Unbounce_API__c = true
        );
        insert intake;
        update new litify_pm__Intake__c(
            Id = intake.Id,
            litify_pm__First_Name__c = firstName,
            litify_pm__Last_Name__c = lastName,
            litify_pm__Email__c = email,
            GCLID__c = firstName == 'Status' ? 'test-gclid' : 'tracked-gclid'
        );
        UnbounceIntakeTrackingService.trackIntake(intake.Id, configId);
        return intake;
    }

    private static void resetCapturedRequests() {
        capturedRequests.clear();
    }

    private static String getRequiredStatusValue(String expectedStatus) {
        for (Schema.PicklistEntry entry :
            litify_pm__Intake__c.litify_pm__Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == expectedStatus) {
                return entry.getValue();
            }
        }
        System.assert(false, 'Expected active Intake status value: ' + expectedStatus);
        return null;
    }

    private static String getDisallowedStatusValue(String currentStatus) {
        for (Schema.PicklistEntry entry :
            litify_pm__Intake__c.litify_pm__Status__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String value = entry.getValue();
            if (value == currentStatus || value == 'Referred Out' || value == 'Converted') {
                continue;
            }
            return value;
        }
        System.assert(false, 'Expected at least one active disallowed Intake status value');
        return null;
    }

    private static void setOptionalIntakeField(litify_pm__Intake__c intake, String fieldName, Object value) {
        if (intake == null || String.isBlank(fieldName) || value == null) {
            return;
        }
        Map<String, Schema.SObjectField> intakeFields =
            litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();
        if (!intakeFields.containsKey(fieldName)) {
            return;
        }
        intake.put(fieldName, value);
    }

    private static Account createReferredByParty(String fallbackName) {
        Account referredByParty = new Account();
        referredByParty.Name = fallbackName;
        try {
            referredByParty.put('litify_pm__Last_Name__c', fallbackName);
        } catch (SObjectException e) {
            for (Schema.SObjectField field : Account.SObjectType.getDescribe().fields.getMap().values()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (describe.getName().toLowerCase().contains('last') &&
                    describe.getType() == Schema.DisplayType.String &&
                    describe.isCreateable()) {
                    referredByParty.put(describe.getName(), fallbackName);
                    break;
                }
            }
        }
        insert referredByParty;
        return [SELECT Id, Name FROM Account WHERE Id = :referredByParty.Id];
    }

    private static String getAdvertisingSourceTypeValue() {
        for (Schema.PicklistEntry entry :
            litify_pm__Intake__c.litify_pm__Source_Type__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            String value = entry.getValue();
            if (value != null && value.toLowerCase().startsWith('advert')) {
                return value;
            }
        }
        return null;
    }

    private static Id createSyntheticIntakeId() {
        return (Id) ('a0d000000000001AAA');
    }

    private static Id createSyntheticConfigId() {
        return (Id) ('a1Y000000000001AAA');
    }

    private static String formatAsIso8601(Datetime value) {
        return value == null ? null : value.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }
}
