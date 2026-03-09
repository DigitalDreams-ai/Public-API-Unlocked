public without sharing class PublicApiRelatedRecordService {
    @TestVisible static final Set<String> MULTI_MATCH_POLICIES =
        new Set<String>{ 'Error', 'UseOldest', 'UseNewest' };
    @TestVisible static final String DEFAULT_MULTI_MATCH_POLICY = 'Error';

    public class RelatedRecordRule {
        @AuraEnabled public String targetLookupField;
        @AuraEnabled public String relatedObjectApiName;
        @AuraEnabled public String matchFieldName;
        @AuraEnabled public String sourceKey;
        @AuraEnabled public Boolean createIfMissing;
        @AuraEnabled public String onMultipleMatches;
        @AuraEnabled public List<CreateFieldMapping> createMappings;
    }

    public class CreateFieldMapping {
        @AuraEnabled public String sourceKey;
        @AuraEnabled public String fieldName;
    }

    public static void applyRelatedRecordRules(
        SObject targetRecord,
        Map<String, Object> payload,
        String relatedRecordConfigurationJson
    ) {
        if (targetRecord == null || payload == null || String.isBlank(relatedRecordConfigurationJson)) {
            return;
        }

        Map<String, Object> data = extractDataMap(payload);
        for (RelatedRecordRule rule : parseRules(relatedRecordConfigurationJson)) {
            if (rule == null) {
                continue;
            }

            ResolvedRule resolvedRule = resolveRule(rule, targetRecord);
            Object rawMatchValue = getPayloadValue(payload, data, resolvedRule.sourceKey);
            if (rawMatchValue == null) {
                continue;
            }

            SObject relatedRecord = findRelatedRecord(resolvedRule, rawMatchValue);
            if (relatedRecord == null && resolvedRule.createIfMissing) {
                relatedRecord = createRelatedRecord(resolvedRule, payload, data, rawMatchValue);
            }
            if (relatedRecord != null) {
                targetRecord.put(resolvedRule.targetLookupFieldApiName, relatedRecord.Id);
            }
        }
    }

    public static void validateRules(
        String relatedRecordConfigurationJson,
        String targetObjectApiName
    ) {
        if (String.isBlank(relatedRecordConfigurationJson)) {
            return;
        }

        if (String.isBlank(targetObjectApiName)) {
            throw new PublicApiIntakeServiceException('Target object API name is required for related record validation.');
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType targetObjectType = resolveSObjectType(targetObjectApiName, globalDescribe);
        if (targetObjectType == null) {
            throw new PublicApiIntakeServiceException('Unknown target object: ' + targetObjectApiName);
        }

        Map<String, Schema.SObjectField> targetFieldMap = targetObjectType.getDescribe().fields.getMap();
        for (RelatedRecordRule rule : parseRules(relatedRecordConfigurationJson)) {
            validateRule(rule, targetObjectType.getDescribe().getName(), targetFieldMap, globalDescribe);
        }
    }

    public static List<RelatedRecordRule> parseRules(String relatedRecordConfigurationJson) {
        List<RelatedRecordRule> rules = new List<RelatedRecordRule>();
        if (String.isBlank(relatedRecordConfigurationJson)) {
            return rules;
        }

        Object parsed = JSON.deserializeUntyped(relatedRecordConfigurationJson);
        if (!(parsed instanceof List<Object>)) {
            throw new PublicApiIntakeServiceException(
                'Related record configuration must be a JSON array of rule rows.'
            );
        }

        Integer sortOrder = 0;
        for (Object entry : (List<Object>) parsed) {
            sortOrder++;
            if (!(entry instanceof Map<String, Object>)) {
                continue;
            }

            RelatedRecordRule rule = fromMap((Map<String, Object>) entry);
            if (rule == null) {
                continue;
            }
            rules.add(rule);
        }
        return rules;
    }

    @TestVisible
    static Set<String> getConfiguredSourceKeys(String relatedRecordConfigurationJson) {
        Set<String> keys = new Set<String>();
        for (RelatedRecordRule rule : parseRules(relatedRecordConfigurationJson)) {
            if (String.isNotBlank(rule.sourceKey)) {
                keys.add(rule.sourceKey.trim());
            }
            if (rule.createMappings == null) {
                continue;
            }
            for (CreateFieldMapping mapping : rule.createMappings) {
                if (mapping != null && String.isNotBlank(mapping.sourceKey)) {
                    keys.add(mapping.sourceKey.trim());
                }
            }
        }
        return keys;
    }

    private class ResolvedRule {
        public String targetLookupFieldApiName;
        public String relatedObjectApiName;
        public String matchFieldApiName;
        public String sourceKey;
        public Boolean createIfMissing;
        public String multiMatchPolicy;
        public List<CreateFieldMapping> createMappings;
        public Schema.DescribeFieldResult matchFieldDescribe;
        public Map<String, Schema.SObjectField> relatedFieldMap;
    }

    private static RelatedRecordRule fromMap(Map<String, Object> entry) {
        if (entry == null) {
            return null;
        }

        RelatedRecordRule rule = new RelatedRecordRule();
        rule.targetLookupField = normalizeString(entry.get('targetLookupField'));
        rule.relatedObjectApiName = normalizeString(entry.get('relatedObjectApiName'));
        rule.matchFieldName = normalizeString(entry.get('matchFieldName'));
        rule.sourceKey = normalizeString(entry.get('sourceKey'));
        rule.createIfMissing = parseBoolean(entry.get('createIfMissing'));
        rule.onMultipleMatches = normalizeString(entry.get('onMultipleMatches'));
        rule.createMappings = parseCreateMappings(entry.get('createMappings'));

        if (String.isBlank(rule.targetLookupField) &&
            String.isBlank(rule.relatedObjectApiName) &&
            String.isBlank(rule.matchFieldName) &&
            String.isBlank(rule.sourceKey) &&
            (rule.createMappings == null || rule.createMappings.isEmpty())) {
            return null;
        }
        return rule;
    }

    private static List<CreateFieldMapping> parseCreateMappings(Object rawMappings) {
        List<CreateFieldMapping> mappings = new List<CreateFieldMapping>();
        if (!(rawMappings instanceof List<Object>)) {
            return mappings;
        }

        for (Object rawEntry : (List<Object>) rawMappings) {
            if (!(rawEntry instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> entry = (Map<String, Object>) rawEntry;
            CreateFieldMapping mapping = new CreateFieldMapping();
            mapping.sourceKey = normalizeString(entry.get('sourceKey'));
            mapping.fieldName = normalizeString(entry.get('fieldName'));
            if (String.isBlank(mapping.sourceKey) && String.isBlank(mapping.fieldName)) {
                continue;
            }
            mappings.add(mapping);
        }
        return mappings;
    }

    private static void validateRule(
        RelatedRecordRule rule,
        String targetObjectApiName,
        Map<String, Schema.SObjectField> targetFieldMap,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (rule == null) {
            return;
        }
        if (String.isBlank(rule.targetLookupField)) {
            throw new PublicApiIntakeServiceException('Related record rule target lookup field is required.');
        }
        if (String.isBlank(rule.relatedObjectApiName)) {
            throw new PublicApiIntakeServiceException('Related record rule related object is required.');
        }
        if (String.isBlank(rule.matchFieldName)) {
            throw new PublicApiIntakeServiceException('Related record rule match field is required.');
        }
        if (String.isBlank(rule.sourceKey)) {
            throw new PublicApiIntakeServiceException('Related record rule source key is required.');
        }

        String resolvedLookupFieldApiName = resolveFieldApiName(rule.targetLookupField, targetFieldMap);
        if (String.isBlank(resolvedLookupFieldApiName)) {
            throw new PublicApiIntakeServiceException(
                'Unknown target lookup field on ' + targetObjectApiName + ': ' + rule.targetLookupField
            );
        }

        Schema.DescribeFieldResult lookupDescribe = targetFieldMap.get(resolvedLookupFieldApiName).getDescribe();
        if (!isLookupField(lookupDescribe)) {
            throw new PublicApiIntakeServiceException(
                'Related record target field must be a lookup or master-detail field: ' + resolvedLookupFieldApiName
            );
        }
        if (!lookupDescribe.isCreateable()) {
            throw new PublicApiIntakeServiceException(
                'Related record target lookup field is read-only: ' + resolvedLookupFieldApiName
            );
        }

        Schema.SObjectType relatedObjectType = resolveSObjectType(rule.relatedObjectApiName, globalDescribe);
        if (relatedObjectType == null) {
            throw new PublicApiIntakeServiceException('Unknown related object: ' + rule.relatedObjectApiName);
        }
        String canonicalRelatedObjectApiName = relatedObjectType.getDescribe().getName();
        if (!referencesObject(lookupDescribe, canonicalRelatedObjectApiName)) {
            throw new PublicApiIntakeServiceException(
                'Lookup field ' + resolvedLookupFieldApiName + ' does not reference ' + canonicalRelatedObjectApiName
            );
        }

        Map<String, Schema.SObjectField> relatedFieldMap = relatedObjectType.getDescribe().fields.getMap();
        String resolvedMatchFieldApiName = resolveFieldApiName(rule.matchFieldName, relatedFieldMap);
        if (String.isBlank(resolvedMatchFieldApiName)) {
            throw new PublicApiIntakeServiceException(
                'Unknown related match field on ' + canonicalRelatedObjectApiName + ': ' + rule.matchFieldName
            );
        }

        Schema.DescribeFieldResult matchDescribe = relatedFieldMap.get(resolvedMatchFieldApiName).getDescribe();
        if (!matchDescribe.isAccessible() || !matchDescribe.isFilterable()) {
            throw new PublicApiIntakeServiceException(
                'Related record match field is not queryable: ' + canonicalRelatedObjectApiName + '.' +
                resolvedMatchFieldApiName
            );
        }

        String multiMatchPolicy = String.isBlank(rule.onMultipleMatches)
            ? DEFAULT_MULTI_MATCH_POLICY
            : rule.onMultipleMatches.trim();
        if (!MULTI_MATCH_POLICIES.contains(multiMatchPolicy)) {
            throw new PublicApiIntakeServiceException(
                'Unsupported related record multiple match policy: ' + multiMatchPolicy
            );
        }

        if (rule.createMappings != null) {
            for (CreateFieldMapping mapping : rule.createMappings) {
                if (mapping == null) {
                    continue;
                }
                if (String.isBlank(mapping.sourceKey) || String.isBlank(mapping.fieldName)) {
                    throw new PublicApiIntakeServiceException(
                        'Related record create mapping rows require both source key and field name.'
                    );
                }

                String resolvedCreateFieldApiName = resolveFieldApiName(mapping.fieldName, relatedFieldMap);
                if (String.isBlank(resolvedCreateFieldApiName)) {
                    throw new PublicApiIntakeServiceException(
                        'Unknown related create field on ' + canonicalRelatedObjectApiName + ': ' + mapping.fieldName
                    );
                }

                Schema.DescribeFieldResult createDescribe = relatedFieldMap.get(resolvedCreateFieldApiName).getDescribe();
                if (!createDescribe.isCreateable()) {
                    throw new PublicApiIntakeServiceException(
                        'Related record create field is read-only: ' + canonicalRelatedObjectApiName + '.' +
                        resolvedCreateFieldApiName
                    );
                }
            }
        }
    }

    private static ResolvedRule resolveRule(RelatedRecordRule rule, SObject targetRecord) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        String targetObjectApiName = targetRecord.getSObjectType().getDescribe().getName();
        Map<String, Schema.SObjectField> targetFieldMap = targetRecord.getSObjectType().getDescribe().fields.getMap();
        validateRule(rule, targetObjectApiName, targetFieldMap, globalDescribe);

        Schema.SObjectType relatedObjectType = resolveSObjectType(rule.relatedObjectApiName, globalDescribe);
        Map<String, Schema.SObjectField> relatedFieldMap = relatedObjectType.getDescribe().fields.getMap();

        ResolvedRule resolved = new ResolvedRule();
        resolved.targetLookupFieldApiName = resolveFieldApiName(rule.targetLookupField, targetFieldMap);
        resolved.relatedObjectApiName = relatedObjectType.getDescribe().getName();
        resolved.matchFieldApiName = resolveFieldApiName(rule.matchFieldName, relatedFieldMap);
        resolved.sourceKey = rule.sourceKey.trim();
        resolved.createIfMissing = rule.createIfMissing == true;
        resolved.multiMatchPolicy = String.isBlank(rule.onMultipleMatches)
            ? DEFAULT_MULTI_MATCH_POLICY
            : rule.onMultipleMatches.trim();
        resolved.createMappings = rule.createMappings == null
            ? new List<CreateFieldMapping>()
            : rule.createMappings;
        resolved.matchFieldDescribe = relatedFieldMap.get(resolved.matchFieldApiName).getDescribe();
        resolved.relatedFieldMap = relatedFieldMap;
        return resolved;
    }

    private static SObject findRelatedRecord(ResolvedRule rule, Object rawMatchValue) {
        Object matchValue = normalizeValueForField(rawMatchValue, rule.matchFieldDescribe);
        if (matchValue == null) {
            return null;
        }

        String orderDirection = rule.multiMatchPolicy == 'UseNewest' ? 'DESC' : 'ASC';
        Integer limitSize = rule.multiMatchPolicy == 'Error' ? 2 : 1;
        String query =
            'SELECT Id, CreatedDate FROM ' + rule.relatedObjectApiName +
            ' WHERE ' + rule.matchFieldApiName + ' = :matchValue' +
            ' ORDER BY CreatedDate ' + orderDirection +
            ' LIMIT ' + limitSize;
        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            return null;
        }
        if (records.size() > 1 && rule.multiMatchPolicy == 'Error') {
            throw new PublicApiIntakeServiceException(
                'Multiple related records matched ' + rule.relatedObjectApiName + '.' + rule.matchFieldApiName +
                ' for source key ' + rule.sourceKey
            );
        }
        return records[0];
    }

    private static SObject createRelatedRecord(
        ResolvedRule rule,
        Map<String, Object> payload,
        Map<String, Object> data,
        Object rawMatchValue
    ) {
        SObject relatedRecord = Schema.getGlobalDescribe().get(rule.relatedObjectApiName).newSObject();
        Set<String> assignedFieldApiNames = new Set<String>();
        for (CreateFieldMapping mapping : rule.createMappings) {
            if (mapping == null || String.isBlank(mapping.sourceKey) || String.isBlank(mapping.fieldName)) {
                continue;
            }

            String resolvedFieldApiName = resolveFieldApiName(mapping.fieldName, rule.relatedFieldMap);
            if (String.isBlank(resolvedFieldApiName)) {
                continue;
            }

            Object rawValue = getPayloadValue(payload, data, mapping.sourceKey);
            Object normalizedValue = normalizeValueForField(
                rawValue,
                rule.relatedFieldMap.get(resolvedFieldApiName).getDescribe()
            );
            if (normalizedValue == null) {
                continue;
            }

            relatedRecord.put(resolvedFieldApiName, normalizedValue);
            assignedFieldApiNames.add(resolvedFieldApiName);
        }

        if (!assignedFieldApiNames.contains(rule.matchFieldApiName) && rule.matchFieldDescribe.isCreateable()) {
            Object normalizedMatchValue = normalizeValueForField(rawMatchValue, rule.matchFieldDescribe);
            if (normalizedMatchValue != null) {
                relatedRecord.put(rule.matchFieldApiName, normalizedMatchValue);
            }
        }

        try {
            insert relatedRecord;
            return relatedRecord;
        } catch (DmlException e) {
            throw new PublicApiIntakeServiceException(
                'Failed to create related ' + rule.relatedObjectApiName + ' record: ' + e.getMessage()
            );
        }
    }

    private static Boolean referencesObject(
        Schema.DescribeFieldResult lookupDescribe,
        String relatedObjectApiName
    ) {
        if (lookupDescribe == null || String.isBlank(relatedObjectApiName)) {
            return false;
        }
        List<Schema.SObjectType> referenceTo = lookupDescribe.getReferenceTo();
        if (referenceTo == null) {
            return false;
        }
        for (Schema.SObjectType objectType : referenceTo) {
            if (objectType != null &&
                objectType.getDescribe().getName().equalsIgnoreCase(relatedObjectApiName)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isLookupField(Schema.DescribeFieldResult describe) {
        if (describe == null) {
            return false;
        }
        Schema.DisplayType typeValue = describe.getType();
        return typeValue == Schema.DisplayType.Reference;
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

    private static String resolveFieldApiName(String requestedFieldName, Map<String, Schema.SObjectField> fieldMap) {
        if (String.isBlank(requestedFieldName) || fieldMap == null || fieldMap.isEmpty()) {
            return null;
        }
        if (fieldMap.containsKey(requestedFieldName)) {
            return requestedFieldName;
        }
        String normalizedFieldName = requestedFieldName.trim().toLowerCase();
        for (String key : fieldMap.keySet()) {
            if (key != null && key.toLowerCase() == normalizedFieldName) {
                return key;
            }
        }
        return null;
    }

    private static Map<String, Object> extractDataMap(Map<String, Object> payload) {
        if (payload != null &&
            payload.containsKey('data') &&
            payload.get('data') instanceof Map<String, Object>) {
            return (Map<String, Object>) payload.get('data');
        }
        return payload;
    }

    private static Object getPayloadValue(Map<String, Object> payload, Map<String, Object> data, String sourceKey) {
        if (String.isBlank(sourceKey)) {
            return null;
        }

        Object value = getValueByPath(data, sourceKey);
        if (value != null) {
            return value;
        }
        if (payload == data) {
            return null;
        }
        return getValueByPath(payload, sourceKey);
    }

    private static Object getValueByPath(Map<String, Object> root, String path) {
        if (root == null || String.isBlank(path)) {
            return null;
        }
        if (root.containsKey(path)) {
            return root.get(path);
        }

        Object current = root;
        for (String token : path.split('\\.')) {
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            Map<String, Object> currentMap = (Map<String, Object>) current;
            if (!currentMap.containsKey(token)) {
                return null;
            }
            current = currentMap.get(token);
        }
        return current;
    }

    private static Object normalizeValueForField(Object rawValue, Schema.DescribeFieldResult describe) {
        if (rawValue == null) {
            return null;
        }

        Object value = rawValue;
        if (value instanceof List<Object>) {
            List<Object> values = (List<Object>) value;
            value = values.isEmpty() ? null : values[0];
        }
        if (value == null) {
            return null;
        }

        String stringValue = String.valueOf(value);
        if (describe == null) {
            return stringValue;
        }

        Schema.DisplayType typeValue = describe.getType();
        if (typeValue == Schema.DisplayType.Boolean) {
            return stringValue != null && stringValue.toLowerCase() == 'true';
        }
        if (typeValue == Schema.DisplayType.Double ||
            typeValue == Schema.DisplayType.Currency ||
            typeValue == Schema.DisplayType.Percent) {
            return Decimal.valueOf(stringValue);
        }
        if (typeValue == Schema.DisplayType.Integer) {
            return Integer.valueOf(stringValue);
        }
        if (typeValue == Schema.DisplayType.Date) {
            return Date.valueOf(stringValue);
        }
        if (typeValue == Schema.DisplayType.DateTime) {
            return Datetime.valueOf(stringValue);
        }
        if (describe.getLength() > 0 && stringValue != null && stringValue.length() > describe.getLength()) {
            return stringValue.substring(0, describe.getLength());
        }
        return stringValue;
    }

    private static String normalizeString(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Boolean parseBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return String.valueOf(value).trim().toLowerCase() == 'true';
    }
}
