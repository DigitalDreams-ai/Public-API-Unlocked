@IsTest
public class UnbounceIntakeApiTest {

    @IsTest
    static void testCreateIntake_Success() {
        litify_pm__Firm__c firm = UnbounceTestDataFactory.createFirm();
        UnbounceTestDataFactory.createCaseType('Auto Accident');

        Unbounce_Config__c config = new Unbounce_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        config.Default_Firm_Id__c = firm.Id;
        config.Default_Case_Type_Name__c = 'Auto Accident';
        upsert config;

        Map<String, Object> payload = new Map<String, Object>{
            'first_name' => 'Jane',
            'last_name' => 'Smith',
            'email' => 'jane@example.com',
            'phone' => '555-123-4567',
            'description' => 'Test intake from Unbounce'
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

        System.assertEquals(201, res.statusCode, 'Expected 201. Body: ' + res.responseBody?.toString());

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
    static void testCreateIntake_InvalidJson() {
        litify_pm__Firm__c firm = UnbounceTestDataFactory.createFirm();
        Unbounce_Config__c config = new Unbounce_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        config.Default_Firm_Id__c = firm.Id;
        upsert config;

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
}
