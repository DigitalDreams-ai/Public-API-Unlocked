@IsTest
public class UnbounceIntakeApiTest {

    @IsTest
    static void testCreateIntake_Success() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');

        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c();
        config.Is_Active__c = true;
        insert config;

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
            SELECT Id
            FROM litify_pm__Intake__c
            WHERE Id = :intakeId
        ];
        System.assertEquals(1, created.size(), 'Intake should exist');
        System.assertNotEquals(null, created[0].Id);
    }

    @IsTest
    static void testCreateIntake_NotConfigured_NoConfig() {
        Map<String, Object> payload = new Map<String, Object>{ 'first_name' => 'Test' };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(503, res.statusCode);
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assert(((String) response.get('errorMessage')).contains('not configured'));
    }

    @IsTest
    static void testCreateIntake_WebFormNoFirm_Success() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c();
        config.Is_Active__c = true;
        insert config;

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
    static void testCreateIntake_ApiKeyRequired_ValidKey() {
        UnbounceTestDataFactory.createCaseType('Auto Accident');
        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c();
        config.Is_Active__c = true;
        config.API_Key__c = 'test-api-key-123';
        insert config;

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
        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c();
        config.Is_Active__c = true;
        config.API_Key__c = 'required-key';
        insert config;

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
        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c();
        config.Is_Active__c = true;
        config.API_Key__c = 'correct-key';
        insert config;

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
        Unbounce_Integration_Config__c config = new Unbounce_Integration_Config__c();
        config.Is_Active__c = true;
        insert config;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/v1/unbounce/intakes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{ invalid }');

        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        UnbounceIntakeApi.createIntake();

        System.assertEquals(400, res.statusCode);
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
    static void testUnbounceIntakeModel_FromPayloadWithDataWrapper() {
        Map<String, Object> data = new Map<String, Object>{
            'firstName' => 'Jane',
            'lastName' => 'Doe',
            'email' => 'jane@test.com'
        };
        Map<String, Object> payload = new Map<String, Object>{ 'data' => data };

        litify_pm__Intake__c intake = UnbounceIntakeModel.fromUnbouncePayload(payload);

        System.assertEquals('Jane', intake.litify_pm__First_Name__c);
        System.assertEquals('Doe', intake.litify_pm__Last_Name__c);
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
}
