@IsTest
private class PublicApiPayloadTemplateServiceTest {
    @IsTest
    static void testDefaultMappingJsonsContainRows() {
        List<PublicApiRequestMappingService.MappingConfig> inboundMappings =
            PublicApiRequestMappingService.parseMappings(
                PublicApiPayloadTemplateService.getDefaultInboundMappingsJson()
            );
        List<PublicApiRequestMappingService.MappingConfig> outboundMappings =
            PublicApiRequestMappingService.parseMappings(
                PublicApiPayloadTemplateService.getDefaultOutboundMappingsJson()
            );

        System.assertEquals(true, inboundMappings.size() > 0);
        System.assertEquals(true, outboundMappings.size() > 0);
    }

    @IsTest
    static void testInferSyncInboundAndOutbound() {
        System.assertEquals(true, PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(null, null));
        System.assertEquals(false, PublicApiPayloadTemplateService.inferSyncInboundAndOutbound('{bad json}', null));

        String sameMappings =
            '[{"externalKey":"status","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}]';
        System.assertEquals(
            true,
            PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(sameMappings, sameMappings)
        );

        String differentMappings =
            '[{"externalKey":"created","value":"$PublicApi_Submission__c.CreatedDate","sortOrder":1}]';
        System.assertEquals(
            false,
            PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(sameMappings, differentMappings)
        );
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
        System.assertEquals(true, inbound.size() > 0);

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

    @IsTest
    static void testGetAvailableTriggerMetadata() {
        List<String> fieldNames = PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(
            'PublicApi_Submission__c'
        );
        System.assertEquals(true, fieldNames.size() > 0);
        System.assertEquals(true, fieldNames.contains(selectPreferredTriggerFieldName('PublicApi_Submission__c')));
        System.assertEquals(false, fieldNames.contains('CreatedDate'));

        List<String> booleanValues = PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(
            'PublicApi_Submission__c',
            selectBooleanCapableTriggerFieldName('PublicApi_Submission__c')
        );
        System.assertEquals(new List<String>{ 'true', 'false' }, booleanValues);

        List<String> missingValues = PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(
            'PublicApi_Submission__c',
            'NotAField__c'
        );
        System.assertEquals(0, missingValues.size());

        List<String> lookupFields = PublicApiPayloadTemplateService.getAvailableLookupFieldNames(
            'PublicApi_Submission__c'
        );
        System.assertEquals(true, lookupFields.contains('PublicApi_Integration_Config__c'));

        List<String> lookupTargets = PublicApiPayloadTemplateService.getAvailableLookupTargetObjectApiNames(
            'PublicApi_Submission__c',
            'PublicApi_Integration_Config__c'
        );
        System.assertEquals(new List<String>{ 'PublicApi_Integration_Config__c' }, lookupTargets);

        List<String> matchFields = PublicApiPayloadTemplateService.getAvailableMatchFieldNames('Account');
        System.assertEquals(true, matchFields.contains('Name'));

        List<String> createFields = PublicApiPayloadTemplateService.getAvailableCreateFieldNames('Account');
        System.assertEquals(true, createFields.contains('Name'));
    }

    private static String selectPreferredTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(objectApiName);
        System.assertEquals(true, fieldNames.size() > 0, 'Expected at least one trigger field.');
        if (fieldNames.contains('Created_By_PublicApi_API__c')) {
            return 'Created_By_PublicApi_API__c';
        }
        if (fieldNames.contains('Status__c')) {
            return 'Status__c';
        }
        return fieldNames[0];
    }

    private static String selectBooleanCapableTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(objectApiName);
        for (String fieldName : fieldNames) {
            List<String> values =
                PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(objectApiName, fieldName);
            if (values.size() == 2 && values[0] == 'true' && values[1] == 'false') {
                return fieldName;
            }
        }
        System.assert(false, 'Expected at least one boolean-style trigger field.');
        return null;
    }
}
