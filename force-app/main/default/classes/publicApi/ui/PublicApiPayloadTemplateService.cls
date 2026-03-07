public without sharing class PublicApiPayloadTemplateService {
    @TestVisible static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';

    @TestVisible
    static final List<PublicApiRequestMappingService.MappingConfig> DEFAULT_INBOUND_MAPPINGS =
        new List<PublicApiRequestMappingService.MappingConfig>();

    @TestVisible
    static final List<PublicApiRequestMappingService.MappingConfig> DEFAULT_OUTBOUND_MAPPINGS =
        new List<PublicApiRequestMappingService.MappingConfig>{
            new PublicApiRequestMappingService.MappingConfig('status', '$PublicApi_Submission__c.Status__c', 10),
            new PublicApiRequestMappingService.MappingConfig('receivedAt', '$PublicApi_Submission__c.Received_At__c', 20),
            new PublicApiRequestMappingService.MappingConfig('createdDate', '$PublicApi_Submission__c.CreatedDate', 30)
        };

    public static String getDefaultMappingsJson() {
        return JSON.serializePretty(toSerializableMap(getDefaultConfiguration()));
    }

    public static List<String> getAvailableObjectApiNames() {
        List<String> objectApiNames = new List<String>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (globalDescribe == null || globalDescribe.isEmpty()) {
            return objectApiNames;
        }

        for (String objectApiName : globalDescribe.keySet()) {
            if (String.isBlank(objectApiName)) {
                continue;
            }
            Schema.DescribeSObjectResult describe = globalDescribe.get(objectApiName).getDescribe();
            if (describe == null || !describe.isQueryable()) {
                continue;
            }
            if (!describe.isCreateable() && !describe.isUpdateable()) {
                continue;
            }
            objectApiNames.add(describe.getName());
        }
        objectApiNames.sort();
        return objectApiNames;
    }

    public static List<String> getAvailableFieldReferences(
        String objectApiName,
        Boolean inboundMode
    ) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (String.isBlank(objectApiName) || !globalDescribe.containsKey(objectApiName)) {
            return new List<String>();
        }

        List<String> references = new List<String>();
        Map<String, Schema.SObjectField> fieldMap = globalDescribe.get(objectApiName).getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>(fieldMap.keySet());
        fieldNames.sort();
        for (String fieldName : fieldNames) {
            Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
            if (inboundMode == true && !describe.isCreateable()) {
                continue;
            }
            if (inboundMode == false && !describe.isAccessible()) {
                continue;
            }
            references.add('$' + objectApiName + '.' + fieldName);
        }
        if (inboundMode == false) {
            references.add('$' + objectApiName + '.CreatedDate');
        }
        references.sort();
        return references;
    }

    public static Boolean inferSyncInboundAndOutbound(String configJson) {
        if (String.isBlank(configJson)) {
            return true;
        }
        try {
            PublicApiRequestMappingService.MappingConfiguration config =
                PublicApiRequestMappingService.parseConfiguration(configJson);
            return areMappingsEquivalent(config.inboundMappings, config.outboundMappings);
        } catch (Exception e) {
            return false;
        }
    }

    private static PublicApiRequestMappingService.MappingConfiguration getDefaultConfiguration() {
        PublicApiRequestMappingService.MappingConfiguration config =
            new PublicApiRequestMappingService.MappingConfiguration();
        config.inboundMappings = cloneMappings(DEFAULT_INBOUND_MAPPINGS);
        config.outboundMappings = cloneMappings(DEFAULT_OUTBOUND_MAPPINGS);
        return config;
    }

    private static List<PublicApiRequestMappingService.MappingConfig> cloneMappings(
        List<PublicApiRequestMappingService.MappingConfig> mappings
    ) {
        List<PublicApiRequestMappingService.MappingConfig> cloned =
            new List<PublicApiRequestMappingService.MappingConfig>();
        if (mappings == null) {
            return cloned;
        }

        for (PublicApiRequestMappingService.MappingConfig mapping : mappings) {
            if (mapping == null) {
                continue;
            }
            cloned.add(
                new PublicApiRequestMappingService.MappingConfig(
                    mapping.externalKey,
                    mapping.value,
                    mapping.sortOrder
                )
            );
        }
        cloned.sort(new MappingSortComparator());
        return cloned;
    }

    private static Map<String, Object> toSerializableMap(
        PublicApiRequestMappingService.MappingConfiguration config
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('inbound', cloneMappings(config == null ? null : config.inboundMappings));
        payload.put('outbound', cloneMappings(config == null ? null : config.outboundMappings));
        return payload;
    }

    private static Boolean areMappingsEquivalent(
        List<PublicApiRequestMappingService.MappingConfig> left,
        List<PublicApiRequestMappingService.MappingConfig> right
    ) {
        List<PublicApiRequestMappingService.MappingConfig> safeLeft =
            left == null ? new List<PublicApiRequestMappingService.MappingConfig>() : left;
        List<PublicApiRequestMappingService.MappingConfig> safeRight =
            right == null ? new List<PublicApiRequestMappingService.MappingConfig>() : right;
        if (safeLeft.size() != safeRight.size()) {
            return false;
        }

        for (Integer index = 0; index < safeLeft.size(); index++) {
            PublicApiRequestMappingService.MappingConfig leftRow = safeLeft[index];
            PublicApiRequestMappingService.MappingConfig rightRow = safeRight[index];
            if (!String.valueOf(leftRow == null ? null : leftRow.externalKey)
                    .equalsIgnoreCase(String.valueOf(rightRow == null ? null : rightRow.externalKey))) {
                return false;
            }
            if (!String.valueOf(leftRow == null ? null : leftRow.value)
                    .equalsIgnoreCase(String.valueOf(rightRow == null ? null : rightRow.value))) {
                return false;
            }
        }
        return true;
    }

    private class MappingSortComparator implements Comparator<PublicApiRequestMappingService.MappingConfig> {
        public Integer compare(
            PublicApiRequestMappingService.MappingConfig left,
            PublicApiRequestMappingService.MappingConfig right
        ) {
            Integer leftOrder = left == null || left.sortOrder == null ? 2147483647 : left.sortOrder;
            Integer rightOrder = right == null || right.sortOrder == null ? 2147483647 : right.sortOrder;
            if (leftOrder != rightOrder) {
                return leftOrder < rightOrder ? -1 : 1;
            }
            String leftKey = left == null || left.externalKey == null ? '' : left.externalKey;
            String rightKey = right == null || right.externalKey == null ? '' : right.externalKey;
            return leftKey.toLowerCase().compareTo(rightKey.toLowerCase());
        }
    }
}
