@IsTest
private class PublicApiRequestMappingServiceTest {
    @IsTest
    static void testApplyInboundMappingsSetsStatus() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        Map<String, Object> payload = new Map<String, Object>{
            'status' => 'Converted'
        };

        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}' +
            '],"outbound":[]}';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('Converted', submission.Status__c);
    }

    @IsTest
    static void testBuildOutboundPayloadFromSubmission() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c(
            Status__c = 'Referred Out'
        );
        insert submission;
        submission = [
            SELECT Id, Status__c, CreatedDate
            FROM PublicApi_Submission__c
            WHERE Id = :submission.Id
        ];

        String mappingsJson =
            '{"inbound":[],"outbound":[' +
                '{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1},' +
                '{"externalKey":"createdDate","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":2}' +
            ']}';

        Map<String, Object> payload = PublicApiRequestMappingService.buildOutboundPayload(
            submission,
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('Referred Out', payload.get('status'));
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
                'meta' => new Map<String, Object>{
                    'status' => 'Converted'
                }
            }
        };

        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"meta.status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}' +
            '],"outbound":[]}';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            payload,
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('Converted', submission.Status__c);
    }

    @IsTest
    static void testApplyInboundMappingsParsesBooleanValues() {
        PublicApi_Submission__c submission = new PublicApi_Submission__c();
        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"createdByApi","value":"$PublicApi_Submission__c.Created_By_PublicApi_API__c","sortOrder":1}' +
            '],"outbound":[]}';

        PublicApiRequestMappingService.applyInboundMappings(
            submission,
            new Map<String, Object>{ 'createdByApi' => 'true' },
            mappingsJson,
            PublicApiRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals(true, submission.Created_By_PublicApi_API__c);
    }

    @IsTest
    static void testValidateMappingsRejectsNonCanonicalPrefixes() {
        String mappingsJson =
            '{"inbound":[' +
                '{"externalKey":"status","value":"$submission.Status__c","sortOrder":1}' +
            '],"outbound":[]}';

        try {
            PublicApiRequestMappingService.validateMappings(
                mappingsJson,
                PublicApiRequestMappingService.DIRECTION_BOTH
            );
            System.assert(false, 'Expected non-canonical prefixes to be rejected.');
        } catch (PublicApiIntakeServiceException e) {
            System.assert(
                e.getMessage().contains('Invalid field reference') ||
                e.getMessage().contains('does not match configured object')
            );
        }
    }
}
