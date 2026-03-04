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
            'gclid' => 'test-gclid-123',
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
                   Created_By_Unbounce_API__c,
                   litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__Description__c,
                   GCLID__c,
                   litify_pm__Case_Type__c,
                   litify_pm__Source_Type__c
            FROM litify_pm__Intake__c
            WHERE Id = :intakeId
        ];
        System.assertEquals(1, created.size(), 'Intake should exist');
        System.assertNotEquals(null, created[0].Id);
        System.assertEquals(true, created[0].Created_By_Unbounce_API__c);
        System.assertEquals('Jane', created[0].litify_pm__First_Name__c);
        System.assertEquals('Smith', created[0].litify_pm__Last_Name__c);
        System.assertEquals('jane@example.com', created[0].litify_pm__Email__c);
        System.assertEquals('555-123-4567', created[0].litify_pm__Phone__c);
        System.assertEquals('Test intake from Unbounce', created[0].litify_pm__Description__c);
        System.assertEquals('test-gclid-123', created[0].GCLID__c);
        System.assertNotEquals(null, created[0].litify_pm__Case_Type__c);
        System.assertEquals(
            UnbounceIntakeModel.getDefaultSourceTypeValue(),
            created[0].litify_pm__Source_Type__c
        );

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
        SObject created = queryIntakeForOptionalFields(
            (String) response.get('intakeId'),
            new List<String>{ 'litify_pm__Source__c', 'litify_pm__Source_Type__c', 'Referred_By__c' }
        );
        System.assertNotEquals(null, created);
        assertOptionalIntakeFieldEquals(created, 'Referred_By__c', null);
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

        SObject created = queryIntakeForOptionalFields(
            (String) response.get('intakeId'),
            new List<String>{ 'Referred_By__c' }
        );
        System.assertNotEquals(null, created);
        assertOptionalIntakeFieldEquals(created, 'Referred_By__c', referredByParty.Id);
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

        SObject created = queryIntakeForOptionalFields(
            (String) response.get('intakeId'),
            new List<String>{ 'litify_pm__Case_Type__c', 'litify_pm__Case_Type__r.Name', 'Type__c', 'Case_Type__c' }
        );
        System.assertNotEquals(null, created);
        assertOptionalIntakeFieldEquals(created, 'Type__c', 'Personal Injury');
        assertOptionalIntakeFieldEquals(created, 'Case_Type__c', 'MVA');
        System.assertNotEquals(null, created.get('litify_pm__Case_Type__c'));
        System.assertEquals('PI - MVA', ((SObject) created.getSObject('litify_pm__Case_Type__r')).get('Name'));
    }

    @IsTest
    static void testCreateIntake_TruncatesLongUnbounceStrings() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        createActiveConfig(DEFAULT_API_KEY, null);

        String longEmailLocalPart = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz';
        String longEmail = longEmailLocalPart + '@example.com';
        String longPhone = '1234567890123456789012345678901234567890EXTENSION';
        String longPageUrl = 'https://example.com/' + String.valueOf(Crypto.getRandomLong()) + '/' +
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz' +
            '?utm_campaign=' +
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz' +
            '&utm_source=google&utm_medium=cpc&utm_content=variant';

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Jane',
            'last_name' => 'Lengthy',
            'email' => longEmail,
            'phone_number' => longPhone,
            'page_url' => longPageUrl,
            'utm_source' => longPageUrl,
            'utm_medium' => longPageUrl,
            'campaignid' => longPageUrl,
            'utm_content' => longPageUrl,
            'how_can_we_help_you' => 'Long-value truncation test',
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

        System.assertEquals(
            201,
            res.statusCode,
            'Expected 201 for oversized Unbounce strings. Body: ' +
            (res.responseBody != null ? res.responseBody.toString() : '')
        );

        String intakeId = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString())).get('intakeId');
        litify_pm__Intake__c created = [
            SELECT litify_pm__Email__c,
                   litify_pm__Phone__c,
                   litify_pm__lit_Exact_Source__c,
                   litify_pm__UTM_Source__c,
                   litify_pm__UTM_Medium__c,
                   litify_pm__UTM_Campaign__c,
                   litify_pm__UTM_Content__c
            FROM litify_pm__Intake__c
            WHERE Id = :intakeId
        ];
        System.assertEquals(80, created.litify_pm__Email__c.length());
        System.assertEquals(40, created.litify_pm__Phone__c.length());
        System.assertEquals(255, created.litify_pm__lit_Exact_Source__c.length());
        System.assertEquals(255, created.litify_pm__UTM_Source__c.length());
        System.assertEquals(255, created.litify_pm__UTM_Medium__c.length());
        System.assertEquals(255, created.litify_pm__UTM_Campaign__c.length());
        System.assertEquals(255, created.litify_pm__UTM_Content__c.length());
    }

    @IsTest
    static void testCreateIntake_MapsGclid() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Jane',
            'last_name' => 'Click',
            'email' => 'jane.click@example.com',
            'phone_number' => '555-020-3030',
            'gclid' => 'EAIaIQobChMI-test-gclid',
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

        System.assertEquals(
            201,
            res.statusCode,
            'Expected 201 when Unbounce sends gclid. Body: ' +
            (res.responseBody != null ? res.responseBody.toString() : '')
        );

        String intakeId = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString())).get('intakeId');
        litify_pm__Intake__c created = [
            SELECT GCLID__c
            FROM litify_pm__Intake__c
            WHERE Id = :intakeId
        ];
        System.assertEquals('EAIaIQobChMI-test-gclid', created.GCLID__c);
    }

    @IsTest
    static void testCreateIntake_IgnoresSourceStringPayload() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Jane',
            'last_name' => 'Source',
            'email' => 'jane.source@example.com',
            'phone_number' => '555-010-1010',
            'caseType' => 'Auto Accident',
            'source' => 'google'
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

        System.assertEquals(
            201,
            res.statusCode,
            'Expected 201 when Unbounce sends source as plain text. Body: ' +
            (res.responseBody != null ? res.responseBody.toString() : '')
        );

        String intakeId = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString())).get('intakeId');
        litify_pm__Intake__c created = [
            SELECT litify_pm__Source__c, litify_pm__Source_Type__c
            FROM litify_pm__Intake__c
            WHERE Id = :intakeId
        ];
        System.assertEquals(null, created.litify_pm__Source__c);
        System.assertEquals(
            UnbounceIntakeModel.getDefaultSourceTypeValue(),
            created.litify_pm__Source_Type__c
        );
    }

    @IsTest
    static void testCreateIntake_NonMvaCaseTypeDoesNotWriteRestrictedPicklist() {
        createActiveConfig(DEFAULT_API_KEY, null);

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Jane',
            'last_name' => 'Labor',
            'email' => 'jane.labor@example.com',
            'phone_number' => '555-010-2020',
            'caseType' => 'Labor Law'
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

        System.assertEquals(
            201,
            res.statusCode,
            'Expected 201 for non-MVA case types. Body: ' +
            (res.responseBody != null ? res.responseBody.toString() : '')
        );

        String intakeId = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString())).get('intakeId');
        SObject created = queryIntakeForOptionalFields(
            intakeId,
            new List<String>{ 'litify_pm__Case_Type__c', 'Type__c', 'Case_Type__c' }
        );
        assertOptionalIntakeFieldEquals(created, 'Case_Type__c', null);
        assertOptionalIntakeFieldEquals(created, 'Type__c', null);
        System.assertEquals(null, created.get('litify_pm__Case_Type__c'));
    }

    @IsTest
    static void testCreateIntake_AppliesDuplicateRuleBypassForUnbounceRecords() {
        litify_pm__Intake__c intake = new litify_pm__Intake__c(
            Created_By_Unbounce_API__c = true
        );

        Database.DMLOptions options = UnbounceIntakeService.buildDuplicateRuleBypassOptions(intake);

        System.assertNotEquals(null, options);
        System.assertEquals(true, options.DuplicateRuleHeader.allowSave);
        System.assertEquals(false, options.DuplicateRuleHeader.runAsCurrentUser);
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
            UnbounceIntakeService.forcedClientAccountCreateFailureMessage = null;
        } finally {
            Test.stopTest();
            UnbounceIntakeService.forcedClientAccountCreateFailureMessage = null;
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
        SObject created = queryIntakeForOptionalFields(
            (String) response.get('intakeId'),
            new List<String>{
                'litify_pm__First_Name__c',
                'litify_pm__Last_Name__c',
                'litify_pm__Email__c',
                'litify_pm__Phone__c',
                'litify_pm__Description__c',
                'litify_pm__lit_Exact_Source__c',
                'litify_pm__Case_Type__r.Name',
                'Type__c',
                'Case_Type__c'
            }
        );
        System.assertEquals('Form', created.get('litify_pm__First_Name__c'));
        System.assertEquals('Encoded', created.get('litify_pm__Last_Name__c'));
        System.assertEquals('form.encoded@example.com', created.get('litify_pm__Email__c'));
        System.assertEquals('5551234567', created.get('litify_pm__Phone__c'));
        System.assertEquals('Need help', created.get('litify_pm__Description__c'));
        System.assertEquals('https://example.com/landing', created.get('litify_pm__lit_Exact_Source__c'));
        assertOptionalIntakeFieldEquals(created, 'Type__c', 'Personal Injury');
        assertOptionalIntakeFieldEquals(created, 'Case_Type__c', 'MVA');
        System.assertEquals('PI - MVA', ((SObject) created.getSObject('litify_pm__Case_Type__r')).get('Name'));
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
        System.assertEquals(
            UnbounceIntakeModel.getDefaultSourceTypeValue(),
            intake.litify_pm__Source_Type__c
        );
    }

    @IsTest
    static void testUnbounceIntakeModel_SplitsFullNameWhenLastNameMissing() {
        Map<String, Object> payload = new Map<String, Object>{
            'name' => 'Jane Mary Doe',
            'email' => 'jane.fullname@example.com'
        };

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        System.assertEquals('Jane', intake.litify_pm__First_Name__c);
        System.assertEquals('Mary Doe', intake.litify_pm__Last_Name__c);
    }

    @IsTest
    static void testUnbounceIntakeModel_ClampEmailPreservesDomain() {
        String longEmail =
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz@example.com';

        String clamped = UnbounceIntakeModel.clampToFieldLength('litify_pm__Email__c', longEmail);

        System.assertEquals(80, clamped.length());
        System.assert(clamped.endsWith('@example.com'));
        System.assert(clamped.contains('@'));
    }

    @IsTest
    static void testUnbounceIntakeModel_ClampTextFieldUsesFieldLength() {
        String longGclid =
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz' +
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz' +
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz' +
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz';

        String clamped = UnbounceIntakeModel.clampToFieldLength('GCLID__c', longGclid);

        System.assertEquals(255, clamped.length());
    }

    @IsTest
    static void testUnbounceIntakeModel_ClampEmailWithoutAtSymbolTruncates() {
        String longValue =
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz';

        String clamped = UnbounceIntakeModel.clampToFieldLength('litify_pm__Email__c', longValue);

        System.assertEquals(80, clamped.length());
        System.assertEquals(longValue.substring(0, 80), clamped);
    }

    @IsTest
    static void testUnbounceIntakeModel_ClampUnknownFieldReturnsOriginalValue() {
        String value = 'unchanged';

        System.assertEquals(
            value,
            UnbounceIntakeModel.clampToFieldLength('Does_Not_Exist__c', value)
        );
    }

    @IsTest
    static void testUnbounceIntakeModel_DefaultSourceTypeUsesAdvertisingCompatibleValue() {
        String sourceTypeValue = UnbounceIntakeModel.getDefaultSourceTypeValue();

        if (sourceTypeValue == null) {
            return;
        }

        System.assert(sourceTypeValue.toLowerCase().startsWith('advert'));
    }

    @IsTest
    static void testUnbounceIntakeModel_LabelStyleKeysAreIgnored() {
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
    static void testUnbounceIntakeModel_RequestMappingsApplyForBothDirection() {
        Map<String, Object> payload = new Map<String, Object>{
            'tracking_id' => 'mapped-gclid',
            'notes' => 'Mapped description'
        };
        String configuration =
            '{' +
                '"inbound":[' +
                    '{"externalKey":"tracking_id","value":"$intake.GCLID__c","sortOrder":1},' +
                    '{"externalKey":"notes","value":"$intake.litify_pm__Description__c","sortOrder":2}' +
                '],' +
                '"outbound":[]' +
            '}';

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(
            payload,
            configuration,
            'Both'
        );

        System.assertEquals('mapped-gclid', intake.GCLID__c);
        System.assertEquals('Mapped description', intake.litify_pm__Description__c);
    }

    @IsTest
    static void testUnbounceIntakeModel_RequestMappingsSkipInboundWhenOutboundOnly() {
        Map<String, Object> payload = new Map<String, Object>{
            'tracking_id' => 'mapped-gclid'
        };
        String configuration =
            '{' +
                '"inbound":[{"externalKey":"tracking_id","value":"$intake.GCLID__c","sortOrder":1}],' +
                '"outbound":[]' +
            '}';

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(
            payload,
            configuration,
            'Outbound'
        );

        System.assertEquals(null, intake.GCLID__c);
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
        SObject created = queryIntakeForOptionalFields(
            (String) response.get('intakeId'),
            new List<String>{
                'litify_pm__First_Name__c',
                'litify_pm__Last_Name__c',
                'litify_pm__Email__c',
                'litify_pm__Phone__c',
                'litify_pm__Description__c',
                'litify_pm__lit_Exact_Source__c',
                'litify_pm__Case_Type__r.Name',
                'Type__c',
                'Case_Type__c'
            }
        );
        System.assertEquals('Json', created.get('litify_pm__First_Name__c'));
        System.assertEquals('Array', created.get('litify_pm__Last_Name__c'));
        System.assertEquals('json.array@example.com', created.get('litify_pm__Email__c'));
        System.assertEquals('5551113333', created.get('litify_pm__Phone__c'));
        System.assertEquals('Need help', created.get('litify_pm__Description__c'));
        System.assertEquals('https://example.com/array', created.get('litify_pm__lit_Exact_Source__c'));
        assertOptionalIntakeFieldEquals(created, 'Type__c', 'Personal Injury');
        assertOptionalIntakeFieldEquals(created, 'Case_Type__c', 'MVA');
        System.assertEquals('PI - MVA', ((SObject) created.getSObject('litify_pm__Case_Type__r')).get('Name'));
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

    private static Unbounce_Integration_Config__c createActiveConfig(String apiKey, String referredByPartyName) {
        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c(
            Is_Active__c = true,
            API_Key__c = apiKey,
            Referred_By_Party_Name__c = referredByPartyName
        );
        insert config;
        return config;
    }

    private static SObject queryIntakeForOptionalFields(String intakeId, List<String> candidateFields) {
        Map<String, Schema.SObjectField> intakeFieldMap = litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();
        List<String> selectedFields = new List<String>{ 'Id' };
        for (String fieldName : candidateFields) {
            if (String.isBlank(fieldName)) {
                continue;
            }

            if (fieldName.contains('.')) {
                String relationshipName = fieldName.substringBefore('.');
                if (relationshipName == 'litify_pm__Case_Type__r' && intakeFieldMap.containsKey('litify_pm__Case_Type__c')) {
                    selectedFields.add(fieldName);
                }
                continue;
            }

            if (intakeFieldMap.containsKey(fieldName)) {
                selectedFields.add(fieldName);
            }
        }

        return Database.query(
            'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM litify_pm__Intake__c WHERE Id = :intakeId LIMIT 1'
        );
    }

    private static void assertOptionalIntakeFieldEquals(SObject intakeRecord, String fieldName, Object expectedValue) {
        if (!litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap().containsKey(fieldName)) {
            return;
        }
        System.assertEquals(expectedValue, intakeRecord.get(fieldName));
    }
}
