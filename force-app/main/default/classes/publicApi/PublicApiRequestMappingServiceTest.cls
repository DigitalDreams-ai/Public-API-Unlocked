@IsTest
private class PublicApiRequestMappingServiceTest {
    @IsTest
    static void testApplyInboundMappingsAndNameSplitWhenLastNameBlank() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        Map<String, Object> payload = new Map<String, Object>{
            'name' => 'Jane Smith',
            'last_name' => '',
            'email' => 'jane@example.com'
        };

        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"name","value":"$submission.First_Name__c","sortOrder":1},' +
                '{"externalKey":"last_name","value":"$submission.Last_Name__c","sortOrder":2},' +
                '{"externalKey":"email","value":"$submission.Email__c","sortOrder":3}' +
            '],"outbound":[]}';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('Jane', submission.First_Name__c);
        System.assertEquals('Smith', submission.Last_Name__c);
        System.assertEquals('jane@example.com', submission.Email__c);
    }

    @IsTest
    static void testBuildOutboundPayloadFromSubmission() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            First_Name__c = 'John',
            Last_Name__c = 'Doe',
            Email__c = 'john@example.com'
        );
        insert submission;
        submission = [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, CreatedDate
            FROM PublicApi_Submission__c
            WHERE Id = :submission.Id
        ];

        String mappingsJson =
            '{"inbound":[],"outbound":[' +
                '{"externalKey":"first_name","value":"$submission.First_Name__c","sortOrder":1},' +
                '{"externalKey":"createdDate","value":"$submission.CreatedDate","sortOrder":2}' +
            ']}';

        Map<String, Object> payload = PublicApiRequestMappingService.buildOutboundPayload(
            submission,
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('John', payload.get('first_name'));
        System.assert(String.valueOf(payload.get('createdDate')).contains('2026-03-04'));
    }
}
