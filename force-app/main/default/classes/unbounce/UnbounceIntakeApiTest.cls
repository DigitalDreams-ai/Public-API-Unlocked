@IsTest
public class UnbounceIntakeApiTest {
    private static final String DEFAULT_API_KEY = 'test-api-key';

    @IsTest
    static void testCreateIntake_Success() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');

        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Jane',
            'last_name' => 'Smith',
            'email' => 'jane@example.com',
            'phone' => '555-123-4567',
            'description' => 'Test intake from Unbounce',
            'caseType' => 'Auto Accident'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        UnbounceIntakeApi.createIntake();
        Test.stopTest();

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assert(response.containsKey('intakeId'));
        System.assertEquals('Intake created successfully', response.get('message'));

        String intakeId = (String) response.get('intakeId');
        List<litify_pm__Intake__c> created = [
            SELECT Id,
                   litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__Description__c,
                   litify_pm__Case_Type__c,
                   litify_pm__Source_Type__c
            FROM litify_pm__Intake__c
            WHERE Id = :intakeId
        ];
        System.assertEquals(1, created.size(), 'Intake should exist');
        System.assertNotEquals(null, created[0].Id);
        System.assertEquals('Jane', created[0].litify_pm__First_Name__c);
        System.assertEquals('Smith', created[0].litify_pm__Last_Name__c);
        System.assertEquals('jane@example.com', created[0].litify_pm__Email__c);
        System.assertEquals('555-123-4567', created[0].litify_pm__Phone__c);
        System.assertEquals('Test intake from Unbounce', created[0].litify_pm__Description__c);
        System.assertNotEquals(null, created[0].litify_pm__Case_Type__c);
        System.assertEquals('Advertising', created[0].litify_pm__Source_Type__c);

        List<Unbounce_Intake_Tracking__c> tracking = [
            SELECT Id, Intake_Id__c, Unbounce_Integration_Config__c
            FROM Unbounce_Intake_Tracking__c
            WHERE Intake_Id__c = :intakeId
        ];
        System.assertEquals(1, tracking.size(), 'A tracking row should be created for each Unbounce intake.');
        System.assertNotEquals(null, tracking[0].Unbounce_Integration_Config__c);
    }

    @IsTest
    static void testCreateIntake_NoMatchingConfigForApiKey_401() {
        Map<String, Object> payload = new Map<String, Object>{ 'first_name' => 'Test' };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', 'missing-config-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(401, res.statusCode);
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assert(((String) response.get('errorMessage')).toLowerCase().contains('api key'));
    }

    @IsTest
    static void testCreateIntake_WebFormNoFirm_Success() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Web',
            'last_name' => 'Form',
            'email' => 'webform@example.com',
            'caseType' => 'Auto Accident'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(201, res.statusCode);
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assert(response.containsKey('intakeId'));
        List<litify_pm__Intake__c> created = [
            SELECT litify_pm__Source__c, litify_pm__Source_Type__c, Referred_By__c
            FROM litify_pm__Intake__c
            WHERE Id = :(String) response.get('intakeId')
        ];
        System.assertEquals(1, created.size());
        System.assertEquals(null, created[0].Referred_By__c, 'Web-form intakes should not have Referred_By set');
    }

    @IsTest
    static void testCreateIntake_ConfigReferredByParty_SetsLookup() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        Account referredByParty = new Account();
        try {
            referredByParty.put('litify_pm__Last_Name__c', 'PMAX-Unbounce');
        } catch (SObjectException e) {
            // Some org shapes require a last-name style field on Account but do not expose the Litify field.
            for (Schema.SObjectField field : Account.SObjectType.getDescribe().fields.getMap().values()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (describe.getName().toLowerCase().contains('last') &&
                    describe.getType() == Schema.DisplayType.String &&
                    describe.isCreateable()) {
                    referredByParty.put(describe.getName(), 'PMAX-Unbounce');
                    break;
                }
            }
        }
        insert referredByParty;
        referredByParty = [SELECT Id, Name FROM Account WHERE Id = :referredByParty.Id];

        createActiveConfig('primary-key', referredByParty.Name);
        createActiveConfig('secondary-key', null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Web',
            'last_name' => 'Form',
            'email' => 'referred@example.com',
            'caseType' => 'Auto Accident'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', 'primary-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());

        List<litify_pm__Intake__c> created = [
            SELECT Referred_By__c
            FROM litify_pm__Intake__c
            WHERE Id = :(String) response.get('intakeId')
        ];
        System.assertEquals(1, created.size());
        System.assertEquals(referredByParty.Id, created[0].Referred_By__c);
    }

    @IsTest
    static void testCreateIntake_MvaRoutesTypeAndLitifyCaseType() {
        UnbounceTestDataFactory.createCaseType('PI - MVA');

        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Mva',
            'last_name' => 'Lead',
            'email' => 'mva@example.com',
            'phone' => '555-000-1111',
            'caseType' => 'MVA'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());

        List<litify_pm__Intake__c> created = [
            SELECT Type__c,
                   Case_Type__c,
                   litify_pm__Case_Type__c,
                   litify_pm__Case_Type__r.Name
            FROM litify_pm__Intake__c
            WHERE Id = :(String) response.get('intakeId')
        ];
        System.assertEquals(1, created.size());
        System.assertEquals('Personal Injury', created[0].Type__c);
        System.assertEquals('MVA', created[0].Case_Type__c);
        System.assertNotEquals(null, created[0].litify_pm__Case_Type__c);
        System.assertEquals('PI - MVA', created[0].litify_pm__Case_Type__r.Name);
    }

    @IsTest
    static void testCreateIntake_DuplicateMatchingApiKeys_503() {
        insert new Unbounce_Integration_Config__c(Is_Active__c = true, API_Key__c = 'duplicate-key');
        insert new Unbounce_Integration_Config__c(Is_Active__c = true, API_Key__c = 'duplicate-key');

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Config',
            'last_name' => 'Conflict'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', 'duplicate-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(503, res.statusCode);
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assert(
            ((String) response.get('errorMessage')).contains('must match the supplied API key')
        );
    }

    @IsTest
    static void testCreateIntake_ClientAccountFailure_QueuesDeferredCreation() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');

        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Guest',
            'last_name' => 'Submitter',
            'email' => 'guest@example.com',
            'phone' => '555-222-1111',
            'description' => 'Guest intake',
            'caseType' => 'Auto Accident'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        try {
            UnbounceIntakeService.forcedClientAccountCreateFailureMessage =
                'User does not have access to Contact Objects';
            UnbounceIntakeApi.createIntake();
        } finally {
            UnbounceIntakeService.forcedClientAccountCreateFailureMessage = null;
            Test.stopTest();
        }

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<litify_pm__Intake__c> created = [
            SELECT litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__Description__c,
                   litify_pm__Client__c
            FROM litify_pm__Intake__c
            WHERE Id = :(String) response.get('intakeId')
        ];
        System.assertEquals(1, created.size());
        System.assertEquals('Guest', created[0].litify_pm__First_Name__c);
        System.assertEquals('Submitter', created[0].litify_pm__Last_Name__c);
        System.assertEquals('guest@example.com', created[0].litify_pm__Email__c);
        System.assertEquals('555-222-1111', created[0].litify_pm__Phone__c);
        System.assertEquals('Guest intake', created[0].litify_pm__Description__c);
        System.assertNotEquals(null, created[0].litify_pm__Client__c);
    }

    @IsTest
    static void testCreateIntake_ApiKeyRequired_ValidKey() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        createActiveConfig('test-api-key-123', null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Api',
            'last_name' => 'User',
            'email' => 'api@example.com',
            'caseType' => 'Auto Accident'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', 'test-api-key-123');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(201, res.statusCode, 'Expected 201 with valid API key. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));
    }

    @IsTest
    static void testCreateIntake_ApiKeyRequired_MissingKey_401() {
        createActiveConfig('required-key', null);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"first_name":"A","last_name":"B","email":"a@b.com"}');
        // no x-api-key header

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(401, res.statusCode);
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assert(((String) response.get('errorMessage')).toLowerCase().contains('api key'));
    }

    @IsTest
    static void testCreateIntake_ApiKeyRequired_WrongKey_401() {
        createActiveConfig('correct-key', null);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"first_name":"A","last_name":"B","email":"a@b.com"}');
        req.headers.put('x-api-key', 'wrong-key');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(401, res.statusCode);
    }

    @IsTest
    static void testCreateIntake_InvalidJson() {
        createActiveConfig(DEFAULT_API_KEY, null);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{ invalid }');
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(400, res.statusCode);
    }

    @IsTest
    static void testCreateIntake_FormEncodedPayload_Success() {
        UnbounceTestDataFactory.createCaseType('PI - MVA');

        createActiveConfig(DEFAULT_API_KEY, null);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.requestBody = Blob.valueOf(
            'first_name=Form&last_name=Encoded&email=form.encoded%40example.com&phone_number=5551234567' +
            '&how_can_we_help_you=Need+help&caseType=MVA&page_url=https%3A%2F%2Fexample.com%2Flanding'
        );
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<litify_pm__Intake__c> created = [
            SELECT litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__Description__c,
                   litify_pm__lit_Exact_Source__c,
                   Type__c,
                   Case_Type__c,
                   litify_pm__Case_Type__r.Name
            FROM litify_pm__Intake__c
            WHERE Id = :(String) response.get('intakeId')
        ];
        System.assertEquals(1, created.size());
        System.assertEquals('Form', created[0].litify_pm__First_Name__c);
        System.assertEquals('Encoded', created[0].litify_pm__Last_Name__c);
        System.assertEquals('form.encoded@example.com', created[0].litify_pm__Email__c);
        System.assertEquals('5551234567', created[0].litify_pm__Phone__c);
        System.assertEquals('Need help', created[0].litify_pm__Description__c);
        System.assertEquals('https://example.com/landing', created[0].litify_pm__lit_Exact_Source__c);
        System.assertEquals('Personal Injury', created[0].Type__c);
        System.assertEquals('MVA', created[0].Case_Type__c);
        System.assertEquals('PI - MVA', created[0].litify_pm__Case_Type__r.Name);
    }

    @IsTest
    static void testUnbounceClient_VerifySignature_SkipWhenNoSecret() {
        System.assertEquals(true, UnbounceClient.verifyWebhookSignature('payload', 'sig', null));
        System.assertEquals(true, UnbounceClient.verifyWebhookSignature('payload', 'sig', ''));
    }

    @IsTest
    static void testUnbounceClient_VerifySignature_InvalidWhenBlank() {
        System.assertEquals(false, UnbounceClient.verifyWebhookSignature('payload', null, 'secret'));
        System.assertEquals(false, UnbounceClient.verifyWebhookSignature('', 'sig', 'secret'));
    }

    @IsTest
    static void testUnbounceIntakeModel_FromPayload() {
        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'John',
            'last_name' => 'Doe',
            'email' => 'john@test.com'
        };

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        System.assertEquals('John', intake.litify_pm__First_Name__c);
        System.assertEquals('Doe', intake.litify_pm__Last_Name__c);
        System.assertEquals('john@test.com', intake.litify_pm__Email__c);
    }

    @IsTest
    static void testUnbounceIntakeModel_LabelStyleKeysRequireCustomMapping() {
        Map<String, Object> payload = new Map<String, Object>{
            'Full Name' => 'Jane Doe',
            'Email Address' => 'jane@test.com',
            'Phone Number' => '555-987-6543',
            'Page URL' => 'https://example.com/form',
            'UTM Source' => 'facebook',
            'Campaign ID' => 'lead-gen',
            'UTM Medium' => 'social',
            'UTM Content' => 'post-1',
            'How can we help you?' => 'Interested in a consultation'
        };

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        System.assertEquals(null, intake.litify_pm__First_Name__c);
        System.assertEquals(null, intake.litify_pm__Last_Name__c);
        System.assertEquals(null, intake.litify_pm__Email__c);
        System.assertEquals(null, intake.litify_pm__Phone__c);
        System.assertEquals(null, intake.litify_pm__Description__c);
        System.assertEquals(null, intake.litify_pm__lit_Exact_Source__c);
        System.assertEquals(null, intake.litify_pm__UTM_Source__c);
        System.assertEquals(null, intake.litify_pm__UTM_Campaign__c);
        System.assertEquals(null, intake.litify_pm__UTM_Medium__c);
        System.assertEquals(null, intake.litify_pm__UTM_Content__c);
    }

    @IsTest
    static void testUnbounceIntakeModel_IgnoresAddressFields() {
        Map<String, Object> payload = new Map<String, Object>{
            'address' => '123 Main St',
            'city' => 'Phoenix',
            'state' => 'AZ',
            'zip' => '85004'
        };

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        System.assertEquals(null, intake.litify_pm__Case_Address_1__c);
        System.assertEquals(null, intake.litify_pm__Case_City__c);
        System.assertEquals(null, intake.litify_pm__Case_State__c);
        System.assertEquals(null, intake.litify_pm__Case_Postal_Code__c);
    }

    @IsTest
    static void testUnbounceIntakeModel_FromPayloadWithDataWrapper() {
        Map<String, Object> data = new Map<String, Object>{
            'name' => 'Jane',
            'last_name' => 'Doe',
            'email' => 'jane@test.com'
        };
        Map<String, Object> payload = new Map<String, Object>{ 'data' => data };

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        System.assertEquals('Jane', intake.litify_pm__First_Name__c);
        System.assertEquals('Doe', intake.litify_pm__Last_Name__c);
    }

    @IsTest
    static void testUnbounceIntakeModel_FromPayloadWithArrayValues() {
        Map<String, Object> payload = new Map<String, Object>{
            'name' => new List<Object>{ 'Jane' },
            'last_name' => new List<Object>{ 'Doe' },
            'email' => new List<Object>{ 'jane.array@test.com' },
            'phone_number' => new List<Object>{ '555-987-6543' },
            'how_can_we_help_you' => new List<Object>{ 'Need help' },
            'page_url' => new List<Object>{ 'https://example.com/landing' }
        };

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        System.assertEquals('Jane', intake.litify_pm__First_Name__c);
        System.assertEquals('Doe', intake.litify_pm__Last_Name__c);
        System.assertEquals('jane.array@test.com', intake.litify_pm__Email__c);
        System.assertEquals('555-987-6543', intake.litify_pm__Phone__c);
        System.assertEquals('Need help', intake.litify_pm__Description__c);
        System.assertEquals('https://example.com/landing', intake.litify_pm__lit_Exact_Source__c);
    }

    @IsTest
    static void testCreateIntake_JsonArrayPayload_Success() {
        UnbounceTestDataFactory.createCaseType('PI - MVA');

        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'name' => new List<Object>{ 'Json' },
            'last_name' => new List<Object>{ 'Array' },
            'email' => new List<Object>{ 'json.array@example.com' },
            'phone_number' => new List<Object>{ '5551113333' },
            'how_can_we_help_you' => new List<Object>{ 'Need help' },
            'caseType' => new List<Object>{ 'MVA' },
            'page_url' => new List<Object>{ 'https://example.com/array' }
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<litify_pm__Intake__c> created = [
            SELECT litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__Description__c,
                   litify_pm__lit_Exact_Source__c,
                   Type__c,
                   Case_Type__c,
                   litify_pm__Case_Type__r.Name
            FROM litify_pm__Intake__c
            WHERE Id = :(String) response.get('intakeId')
        ];
        System.assertEquals(1, created.size());
        System.assertEquals('Json', created[0].litify_pm__First_Name__c);
        System.assertEquals('Array', created[0].litify_pm__Last_Name__c);
        System.assertEquals('json.array@example.com', created[0].litify_pm__Email__c);
        System.assertEquals('5551113333', created[0].litify_pm__Phone__c);
        System.assertEquals('Need help', created[0].litify_pm__Description__c);
        System.assertEquals('https://example.com/array', created[0].litify_pm__lit_Exact_Source__c);
        System.assertEquals('Personal Injury', created[0].Type__c);
        System.assertEquals('MVA', created[0].Case_Type__c);
        System.assertEquals('PI - MVA', created[0].litify_pm__Case_Type__r.Name);
    }

    @IsTest
    static void testCreateIntake_CustomMapping_LabelStylePayload_Success() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        createActiveConfig(DEFAULT_API_KEY, null);
        insert new Unbounce_Field_Mapping__c(
            Is_Active__c = true,
            Context__c = 'Unbounce Intake',
            Mapping_Configuration__c =
                '{"first_name":"$.data.First Name","last_name":"$.data.Last Name","email":"$.data.Email Address","phone":"$.data.Phone Number","description":"$.data.How can we help you?","caseType":"$.data.Case Type"}'
        );

        Map<String, Object> payload = new Map<String, Object>{
            'data' => new Map<String, Object>{
                'First Name' => 'Label',
                'Last Name' => 'Style',
                'Email Address' => 'label@example.com',
                'Phone Number' => '555-111-2222',
                'How can we help you?' => 'Need help',
                'Case Type' => 'Auto Accident'
            }
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        req.headers.put('x-api-key', DEFAULT_API_KEY);

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + (res.responseBody != null ? res.responseBody.toString() : ''));

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        List<litify_pm__Intake__c> created = [
            SELECT litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__Description__c,
                   litify_pm__Case_Type__c
            FROM litify_pm__Intake__c
            WHERE Id = :(String) response.get('intakeId')
        ];
        System.assertEquals(1, created.size());
        System.assertEquals('Label', created[0].litify_pm__First_Name__c);
        System.assertEquals('Style', created[0].litify_pm__Last_Name__c);
        System.assertEquals('label@example.com', created[0].litify_pm__Email__c);
        System.assertEquals('555-111-2222', created[0].litify_pm__Phone__c);
        System.assertEquals('Need help', created[0].litify_pm__Description__c);
        System.assertNotEquals(null, created[0].litify_pm__Case_Type__c);
    }

    @IsTest
    static void testUnbounceIntakeModel_NullPayloadThrows() {
        try {
            UnbounceIntakeModel.fromUnbouncePayload(null);
            System.assert(false, 'Expected exception');
        } catch (UnbounceIntakeServiceException e) {
            System.assert(e.getMessage().contains('null'));
        }
    }

    @IsTest
    static void testUnbounceCustomMappingService_NoMapping_ReturnsPayloadUnchanged() {
        Map<String, Object> payload = new Map<String, Object>{ 'email' => 'test@example.com' };
        Map<String, Object> result = UnbounceCustomMappingService.applyMapping(payload);
        System.assertEquals(payload, result);
        System.assertEquals('test@example.com', result.get('email'));
    }

    @IsTest
    static void testUnbounceCustomMappingService_WithMapping_TransformsPayload() {
        Unbounce_Field_Mapping__c mapping = new Unbounce_Field_Mapping__c(
            Is_Active__c = true,
            Context__c = 'Unbounce Intake',
            Mapping_Configuration__c = '{"name":"$.data.firstName","email":"$.data.email"}'
        );
        insert mapping;

        Map<String, Object> data = new Map<String, Object>{
            'firstName' => 'MappedFirst',
            'email' => 'mapped@test.com'
        };
        Map<String, Object> payload = new Map<String, Object>{ 'data' => data };

        Map<String, Object> result = UnbounceCustomMappingService.applyMapping(payload);

        System.assertNotEquals(null, result);
        System.assertEquals('MappedFirst', result.get('name'));
        System.assertEquals('mapped@test.com', result.get('email'));
    }

    private static Unbounce_Integration_Config__c createActiveConfig(String apiKey, String referredByPartyName) {
        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = apiKey,
            Referred_By_Party_Name__c = referredByPartyName
        );
        insert config;
        return config;
    }
}
