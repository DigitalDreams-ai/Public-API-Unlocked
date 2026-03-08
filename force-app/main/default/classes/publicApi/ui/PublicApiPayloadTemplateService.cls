public without sharing class PublicApiPayloadTemplateService {
    @TestVisible static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';

    @TestVisible
    static final List<PublicApiRequestMappingService.MappingConfig> DEFAULT_INBOUND_MAPPINGS =
        new List<PublicApiRequestMappingService.MappingConfig>{
            new PublicApiRequestMappingService.MappingConfig('status', '$PublicApi_Submission__c.Status__c', 10)
        };

    @TestVisible
    static final List<PublicApiRequestMappingService.MappingConfig> DEFAULT_OUTBOUND_MAPPINGS =
        new List<PublicApiRequestMappingService.MappingConfig>{
            new PublicApiRequestMappingService.MappingConfig('status', '$PublicApi_Submission__c.Status__c', 10),
            new PublicApiRequestMappingService.MappingConfig('receivedAt', '$PublicApi_Submission__c.Received_At__c', 20),
            new PublicApiRequestMappingService.MappingConfig('createdDate', '$PublicApi_Submission__c.CreatedDate', 30)
        };

    public static String getDefaultInboundMappingsJson() {
        return JSON.serializePretty(cloneMappings(DEFAULT_INBOUND_MAPPINGS));
    }

    public static String getDefaultOutboundMappingsJson() {
        return JSON.serializePretty(cloneMappings(DEFAULT_OUTBOUND_MAPPINGS));
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
            if (!isUsableTargetObject(describe)) {
                continue;
            }
            objectApiNames.add(describe.getName());
        }
        objectApiNames.sort();
        return objectApiNames;
    }

    public static List<String> getAvailableFieldReferences(String objectApiName, Boolean inboundMode) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (String.isBlank(objectApiName)) {
            return new List<String>();
        }

        Schema.SObjectType objectType = resolveSObjectType(objectApiName, globalDescribe);
        if (objectType == null) {
            return new List<String>();
        }

        String canonicalObjectApiName = objectType.getDescribe().getName();
        List<String> references = new List<String>();
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>(fieldMap.keySet());
        fieldNames.sort();
        for (String fieldName : fieldNames) {
            Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
            if (inboundMode && !describe.isCreateable()) {
                continue;
            }
            if (!inboundMode && !describe.isAccessible()) {
                continue;
            }
            references.add('$' + canonicalObjectApiName + '.' + describe.getName());
        }
        if (!inboundMode) {
            references.add('$' + canonicalObjectApiName + '.CreatedDate');
        }
        references.sort();
        return references;
    }

    public static List<String> getAvailableTriggerFieldNames(String objectApiName) {
        Schema.SObjectType objectType = resolveSObjectType(objectApiName, Schema.getGlobalDescribe());
        if (objectType == null) {
            return new List<String>();
        }

        List<String> fieldNames = new List<String>();
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult describe = fieldMap.get(fieldName).getDescribe();
            if (isUsableTriggerField(describe)) {
                fieldNames.add(describe.getName());
            }
        }
        fieldNames.sort();
        return fieldNames;
    }

    public static List<String> getAvailableTriggerFieldValues(String objectApiName, String fieldName) {
        Schema.DescribeFieldResult describe = resolveFieldDescribe(objectApiName, fieldName);
        if (describe == null) {
            return new List<String>();
        }

        List<String> values = new List<String>();
        if (describe.getType() == Schema.DisplayType.Boolean) {
            values.add('true');
            values.add('false');
            return values;
        }

        if (describe.getType() == Schema.DisplayType.Picklist ||
            describe.getType() == Schema.DisplayType.MultiPicklist) {
            for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                if (entry != null && entry.isActive()) {
                    values.add(entry.getValue());
                }
            }
            values.sort();
        }
        return values;
    }

    public static Boolean inferSyncInboundAndOutbound(String inboundConfigJson, String outboundConfigJson) {
        if (String.isBlank(inboundConfigJson) && String.isBlank(outboundConfigJson)) {
            return true;
        }

        try {
            List<PublicApiRequestMappingService.MappingConfig> inboundMappings =
                PublicApiRequestMappingService.parseMappings(inboundConfigJson);
            List<PublicApiRequestMappingService.MappingConfig> outboundMappings =
                PublicApiRequestMappingService.parseMappings(outboundConfigJson);
            return areMappingsEquivalent(inboundMappings, outboundMappings);
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean isUsableTargetObject(Schema.DescribeSObjectResult describe) {
        if (describe == null ||
            !describe.isQueryable() ||
            !describe.isCreateable() ||
            describe.isDeprecatedAndHidden() ||
            describe.isCustomSetting()) {
            return false;
        }

        String objectApiName = describe.getName();
        if (String.isBlank(objectApiName)) {
            return false;
        }

        List<String> excludedSuffixes = new List<String>{
            'History',
            'Feed',
            'Share',
            'Tag',
            'ChangeEvent',
            '__History',
            '__Feed',
            '__Share',
            '__Tag',
            '__ChangeEvent',
            '__mdt',
            '__e',
            '__b'
        };
        for (String suffix : excludedSuffixes) {
            if (objectApiName.endsWith(suffix)) {
                return false;
            }
        }
        return true;
    }

    private static Boolean isUsableTriggerField(Schema.DescribeFieldResult describe) {
        if (describe == null ||
            !describe.isAccessible() ||
            describe.isCalculated() ||
            describe.isAutoNumber()) {
            return false;
        }

        String fieldName = describe.getName();
        Set<String> excludedFieldNames = new Set<String>{
            'Id',
            'CreatedDate',
            'CreatedById',
            'LastModifiedDate',
            'LastModifiedById',
            'SystemModstamp',
            'LastViewedDate',
            'LastReferencedDate'
        };
        if (excludedFieldNames.contains(fieldName)) {
            return false;
        }

        Schema.DisplayType fieldType = describe.getType();
        return fieldType != Schema.DisplayType.Address &&
            fieldType != Schema.DisplayType.Location &&
            fieldType != Schema.DisplayType.Base64;
    }

    private static Schema.SObjectType resolveSObjectType(
        String objectApiName,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (String.isBlank(objectApiName) || globalDescribe == null || globalDescribe.isEmpty()) {
            return null;
        }
        if (globalDescribe.containsKey(objectApiName)) {
            return globalDescribe.get(objectApiName);
        }

        String normalizedObjectApiName = objectApiName.trim().toLowerCase();
        for (String key : globalDescribe.keySet()) {
            if (key != null && key.toLowerCase() == normalizedObjectApiName) {
                return globalDescribe.get(key);
            }
        }
        return null;
    }

    private static Schema.DescribeFieldResult resolveFieldDescribe(String objectApiName, String fieldName) {
        if (String.isBlank(fieldName)) {
            return null;
        }

        Schema.SObjectType objectType = resolveSObjectType(objectApiName, Schema.getGlobalDescribe());
        if (objectType == null) {
            return null;
        }

        String normalizedFieldName = fieldName.trim().toLowerCase();
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        for (String candidateFieldName : fieldMap.keySet()) {
            if (candidateFieldName != null && candidateFieldName.toLowerCase() == normalizedFieldName) {
                return fieldMap.get(candidateFieldName).getDescribe();
            }
        }
        return null;
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
