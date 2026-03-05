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
                '{"externalKey":"name","value":"$intakes.First_Name__c","sortOrder":1},' +
                '{"externalKey":"last_name","value":"$intakes.Last_Name__c","sortOrder":2},' +
                '{"externalKey":"email","value":"$intakes.Email__c","sortOrder":3}' +
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
                '{"externalKey":"first_name","value":"$intakes.First_Name__c","sortOrder":1},' +
                '{"externalKey":"createdDate","value":"$intakes.CreatedDate","sortOrder":2}' +
            ']}';

        Map<String, Object> payload = PublicApiRequestMappingService.buildOutboundPayload(
            submission,
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('John', payload.get('first_name'));
        String createdDate = String.valueOf(payload.get('createdDate'));
        System.assert(String.isNotBlank(createdDate));
        System.assert(createdDate.contains('T'));
        System.assert(createdDate.endsWith('Z'));
    }

    @IsTest
    static void testApplyInboundMappingsSupportsNestedExternalKeys() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        Map<String, Object> payload = new Map<String, Object>{
            'data' => new Map<String, Object>{
                'contact' => new Map<String, Object>{
                    'email' => 'nested@example.com'
                }
            }
        };

        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"contact.email","value":"$intakes.Email__c","sortOrder":1}' +
            '],"outbound":[]}';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('nested@example.com', submission.Email__c);
    }

    @IsTest
    static void testApplyInboundMappingsClampEmailPreservesDomain() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        String longEmail =
            'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz@example.com';
        Integer maxLength = PublicApi_Submission__c.Email__c.getDescribe().getLength();

        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"email","value":"$intakes.Email__c","sortOrder":1}' +
            '],"outbound":[]}';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            new Map<String, Object>{ 'email' => longEmail },
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertNotEquals(null, submission.Email__c);
        System.assertEquals(maxLength, submission.Email__c.length());
        System.assert(submission.Email__c.contains('@'));
        System.assert(submission.Email__c.endsWith('@example.com'));
    }

    @IsTest
    static void testValidateMappingsRejectsNonCanonicalPrefixes() {
        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"email","value":"$submission.Email__c","sortOrder":1}' +
            '],"outbound":[]}';

        try {
            PublicApiRequestMappingService.validateMappings(
                mappingsJson,
                PublicApiRequestMappingService.DIRECTION_BOTH
            );
            System.assert(false, 'Expected non-canonical prefixes to be rejected.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(e.getMessage().contains('Invalid field reference'));
        }
    }
}
