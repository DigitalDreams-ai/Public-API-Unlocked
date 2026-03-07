@IsTest
private class PublicApiPayloadTemplateServiceTest {
    @IsTest
    static void testGetDefaultMappingsJsonContainsInboundAndOutbound() {
        String jsonValue = PublicApiPayloadTemplateService.getDefaultMappingsJson();
        PublicApiRequestMappingService.MappingConfiguration parsed =
            PublicApiRequestMappingService.parseConfiguration(jsonValue);

        System.assertNotEquals(null, parsed);
        System.assertNotEquals(null, parsed.inboundMappings);
        System.assertNotEquals(null, parsed.outboundMappings);
        System.assertEquals(true, parsed.outboundMappings.size() > 0);
    }

    @IsTest
    static void testInferSyncInboundAndOutbound() {
        System.assertEquals(true, PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(null));
        System.assertEquals(false, PublicApiPayloadTemplateService.inferSyncInboundAndOutbound('{bad json}'));

        String sameMappings =
            '{"inbound":[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}],' +
            '"outbound":[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]}';
        System.assertEquals(true, PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(sameMappings));

        String differentMappings =
            '{"inbound":[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}],' +
            '"outbound":[{"externalKey":"created","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":1}]}';
        System.assertEquals(false, PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(differentMappings));
    }

    @IsTest
    static void testGetAvailableObjectApiNamesIncludesSubmissionObject() {
        List<String> objects = PublicApiPayloadTemplateService.getAvailableObjectApiNames();
        System.assertEquals(true, objects.contains('PublicApi_Submission__c'));
    }

    @IsTest
    static void testGetAvailableFieldReferences() {
        List<String> inbound = PublicApiPayloadTemplateService.getAvailableFieldReferences(
            'PublicApi_Submission__c',
            true
        );
        System.assertNotEquals(null, inbound);

        List<String> outbound = PublicApiPayloadTemplateService.getAvailableFieldReferences(
            'PublicApi_Submission__c',
            false
        );
        System.assertEquals(true, outbound.contains('$PublicApi_Submission__c.CreatedDate'));

        List<String> missing = PublicApiPayloadTemplateService.getAvailableFieldReferences(
            'Not_A_Real_Object__c',
            true
        );
        System.assertEquals(0, missing.size());
    }
}
