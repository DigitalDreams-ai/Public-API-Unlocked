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

        String literalInboundMappings =
            '[' +
                '{"sourceType":"LiteralValue","literalValue":"Manual","value":"$PublicApi_Submission__c.Status__c","sortOrder":1}' +
            ']';
        System.assertEquals(
            false,
            PublicApiPayloadTemplateService.inferSyncInboundAndOutbound(literalInboundMappings, sameMappings)
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
        List<String> fieldNames = PublicApiPayloadTemplateService.getAvailableTriggerFieldNames('Task');
        System.assertEquals(true, fieldNames.size() > 0);
        System.assertEquals(true, fieldNames.contains(selectPreferredTriggerFieldName('Task')));
        System.assertEquals(false, fieldNames.contains('CreatedDate'));

        String constrainedTriggerFieldName =
            selectValueConstrainedTriggerFieldName('Task');
        if (constrainedTriggerFieldName != null) {
            List<String> constrainedValues = PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(
                'Task',
                constrainedTriggerFieldName
            );
            System.assertEquals(true, constrainedValues.size() > 0);
        }

        List<String> missingValues = PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(
            'Task',
            'NotAField__c'
        );
        System.assertEquals(0, missingValues.size());

        List<String> lookupFields = PublicApiPayloadTemplateService.getAvailableLookupFieldNames(
            'PublicApi_Submission__c'
        );
        System.assertNotEquals(null, lookupFields);
        List<String> relatedObjects = PublicApiPayloadTemplateService.getAvailableRelatedObjectApiNames('Task');
        System.assertNotEquals(null, relatedObjects);

        if (!relatedObjects.isEmpty()) {
            List<String> taskLookupFields =
                PublicApiPayloadTemplateService.getAvailableLookupFieldNamesForRelatedObject('Task', relatedObjects[0]);
            System.assertNotEquals(null, taskLookupFields);
        }

        List<String> matchFields = PublicApiPayloadTemplateService.getAvailableMatchFieldNames('Account');
        System.assertNotEquals(null, matchFields);

        List<String> createFields = PublicApiPayloadTemplateService.getAvailableCreateFieldNames('Account');
        System.assertNotEquals(null, createFields);

        List<String> requiredCreateFields = PublicApiPayloadTemplateService.getRequiredCreateFieldNames('Task');
        System.assertNotEquals(null, requiredCreateFields);
    }

    @IsTest
    static void testRequiredCreateFieldsExcludeDerivedNameFields() {
        Map<String, Schema.SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        if (fieldMap.containsKey('Name') &&
            PublicApiPayloadTemplateService.hasDerivedNameComponents(fieldMap)) {
            List<String> requiredCreateFields = PublicApiPayloadTemplateService.getRequiredCreateFieldNames('Account');
            System.assertEquals(false, requiredCreateFields.contains('Name'));
        }
    }

    private static String selectPreferredTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(objectApiName);
        System.assertEquals(true, fieldNames.size() > 0, 'Expected at least one trigger field.');
        if (fieldNames.contains('Processing_Status__c')) {
            return 'Processing_Status__c';
        }
        if (fieldNames.contains('Status')) {
            return 'Status';
        }
        if (fieldNames.contains('Status__c')) {
            return 'Status__c';
        }
        if (fieldNames.contains('Priority')) {
            return 'Priority';
        }
        return fieldNames[0];
    }

    private static String selectValueConstrainedTriggerFieldName(String objectApiName) {
        List<String> fieldNames = PublicApiPayloadTemplateService.getAvailableTriggerFieldNames(objectApiName);
        for (String fieldName : fieldNames) {
            List<String> values =
                PublicApiPayloadTemplateService.getAvailableTriggerFieldValues(objectApiName, fieldName);
            if (!values.isEmpty()) {
                return fieldName;
            }
        }
        return null;
    }
}
