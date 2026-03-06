public without sharing class PublicApiRequestMappingService {
    @TestVisible static final String DIRECTION_INBOUND = 'Inbound';
    @TestVisible static final String DIRECTION_OUTBOUND = 'Outbound';
    @TestVisible static final String DIRECTION_BOTH = 'Both';
    @TestVisible static final String DEFAULT_OBJECT_API_NAME = 'PublicApi_Submission__c';

    public class MappingConfig {
        @AuraEnabled public String externalKey;
        @AuraEnabled public String value;
        @AuraEnabled public Integer sortOrder;

        public MappingConfig() {}
        public MappingConfig(String externalKey, String value, Integer sortOrder) {
            this.externalKey = externalKey;
            this.value = value;
            this.sortOrder = sortOrder;
        }
    }

    public class MappingConfiguration {
        @AuraEnabled public List<MappingConfig> inboundMappings = new List<MappingConfig>();
        @AuraEnabled public List<MappingConfig> outboundMappings = new List<MappingConfig>();
    }

    public class FieldReference {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;

        public FieldReference() {}
        public FieldReference(String objectApiName, String fieldApiName) {
            this.objectApiName = objectApiName;
            this.fieldApiName = fieldApiName;
        }
    }

    public static String getDefaultDirection() {
        return DIRECTION_BOTH;
    }

    public static void applyInboundMappings(
        SObject targetRecord,
        Map<String, Object> payload,
        String configJson,
        String direction
    ) {
        String targetObjectApiName = targetRecord == null
            ? null
            : targetRecord.getSObjectType().getDescribe().getName();
        applyInboundMappings(targetRecord, payload, configJson, direction, targetObjectApiName);
    }

    public static void applyInboundMappings(
        SObject targetRecord,
        Map<String, Object> payload,
        String configJson,
        String direction,
        String inboundTargetObjectApiName
    ) {
        if (targetRecord == null || payload == null || !appliesToInbound(direction)) {
            return;
        }

        String recordObjectApiName = targetRecord.getSObjectType().getDescribe().getName();
        String expectedObjectApiName = String.isBlank(inboundTargetObjectApiName)
            ? recordObjectApiName
            : inboundTargetObjectApiName.trim();
        if (!equalsIgnoreCase(recordObjectApiName, expectedObjectApiName)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = targetRecord.getSObjectType().getDescribe().fields.getMap();
        Map<String, Object> data = extractDataMap(payload);
        for (MappingConfig mapping : getEffectiveInboundMappings(configJson, direction)) {
            FieldReference reference = parseFieldReference(mapping == null ? null : mapping.value);
            if (reference == null || !equalsIgnoreCase(reference.objectApiName, recordObjectApiName)) {
                continue;
            }

            String resolvedFieldApiName = resolveFieldApiName(reference.fieldApiName, fieldMap);
            if (String.isBlank(resolvedFieldApiName)) {
                continue;
            }

            Object rawValue = getPayloadValue(payload, data, mapping.externalKey);
            if (rawValue == null) {
                continue;
            }

            try {
                targetRecord.put(
                    resolvedFieldApiName,
                    normalizeInboundValue(rawValue, fieldMap.get(resolvedFieldApiName).getDescribe())
                );
            } catch (Exception e) {
                continue;
            }
        }

        applyNameSplitIfNeeded(targetRecord, data, fieldMap);
    }

    public static Map<String, Object> buildOutboundPayload(
        SObject sourceRecord,
        String configJson,
        String direction
    ) {
        String sourceObjectApiName = sourceRecord == null
            ? null
            : sourceRecord.getSObjectType().getDescribe().getName();
        return buildOutboundPayload(sourceRecord, configJson, direction, sourceObjectApiName);
    }

    public static Map<String, Object> buildOutboundPayload(
        SObject sourceRecord,
        String configJson,
        String direction,
        String outboundSourceObjectApiName
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        if (sourceRecord == null || !appliesToOutbound(direction)) {
            return payload;
        }

        String recordObjectApiName = sourceRecord.getSObjectType().getDescribe().getName();
        if (String.isNotBlank(outboundSourceObjectApiName) &&
            !equalsIgnoreCase(recordObjectApiName, outboundSourceObjectApiName)) {
            return payload;
        }

        Map<String, Schema.SObjectField> fieldMap = sourceRecord.getSObjectType().getDescribe().fields.getMap();
        for (MappingConfig mapping : getEffectiveOutboundMappings(configJson, direction)) {
            FieldReference reference = parseFieldReference(mapping == null ? null : mapping.value);
            if (reference == null || !equalsIgnoreCase(reference.objectApiName, recordObjectApiName)) {
                continue;
            }

            if (equalsIgnoreCase(reference.fieldApiName, 'CreatedDate')) {
                payload.put(mapping.externalKey, normalizeOutboundValue(sourceRecord.get('CreatedDate')));
                continue;
            }

            String resolvedFieldApiName = resolveFieldApiName(reference.fieldApiName, fieldMap);
            if (String.isBlank(resolvedFieldApiName)) {
                continue;
            }

            try {
                payload.put(mapping.externalKey, normalizeOutboundValue(sourceRecord.get(resolvedFieldApiName)));
            } catch (Exception e) {
                continue;
            }
        }
        return payload;
    }

    public static Set<String> getOutboundFieldApiNames(String configJson, String direction) {
        return getOutboundFieldApiNames(configJson, direction, DEFAULT_OBJECT_API_NAME);
    }

    public static Set<String> getOutboundFieldApiNames(
        String configJson,
        String direction,
        String outboundSourceObjectApiName
    ) {
        Set<String> fieldApiNames = new Set<String>();
        if (!appliesToOutbound(direction) || String.isBlank(outboundSourceObjectApiName)) {
            return fieldApiNames;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objectType = resolveSObjectType(outboundSourceObjectApiName, globalDescribe);
        if (objectType == null) {
            return fieldApiNames;
        }
        Map<String, Schema.SObjectField> validFields = objectType.getDescribe().fields.getMap();
        String canonicalObjectApiName = objectType.getDescribe().getName();

        for (MappingConfig mapping : getEffectiveOutboundMappings(configJson, direction)) {
            FieldReference reference = parseFieldReference(mapping == null ? null : mapping.value);
            if (reference == null || !equalsIgnoreCase(reference.objectApiName, canonicalObjectApiName)) {
                continue;
            }
            if (equalsIgnoreCase(reference.fieldApiName, 'CreatedDate')) {
                fieldApiNames.add('CreatedDate');
                continue;
            }
            String resolvedFieldApiName = resolveFieldApiName(reference.fieldApiName, validFields);
            if (String.isNotBlank(resolvedFieldApiName)) {
                fieldApiNames.add(resolvedFieldApiName);
            }
        }
        return fieldApiNames;
    }

    public static void validateMappings(String configJson, String direction) {
        validateMappings(configJson, direction, DEFAULT_OBJECT_API_NAME, DEFAULT_OBJECT_API_NAME);
    }

    public static void validateMappings(
        String configJson,
        String direction,
        String inboundTargetObjectApiName,
        String outboundSourceObjectApiName
    ) {
        if (String.isBlank(configJson)) {
            return;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        MappingConfiguration config = parseConfiguration(configJson);

        if (appliesToInbound(direction)) {
            validateDirectionalMappings(
                config.inboundMappings,
                inboundTargetObjectApiName,
                true,
                globalDescribe
            );
        }
        if (appliesToOutbound(direction)) {
            validateDirectionalMappings(
                config.outboundMappings,
                outboundSourceObjectApiName,
                false,
                globalDescribe
            );
        }
    }

    @TestVisible
    public static MappingConfiguration parseConfiguration(String configJson) {
        if (String.isBlank(configJson)) {
            return new MappingConfiguration();
        }

        Object parsed = JSON.deserializeUntyped(configJson);
        if (!(parsed instanceof Map<String, Object>)) {
            throw new PublicApiIntakeServiceException(
                'Request field mappings configuration must be a JSON object with inbound and outbound arrays.'
            );
        }

        Map<String, Object> root = (Map<String, Object>) parsed;
        MappingConfiguration config = new MappingConfiguration();
        config.inboundMappings = parseMappingArray(root.get('inbound'));
        config.outboundMappings = parseMappingArray(root.get('outbound'));
        return config;
    }

    @TestVisible
    static FieldReference parseFieldReference(String fieldReference) {
        if (String.isBlank(fieldReference)) {
            return null;
        }

        String trimmed = fieldReference.trim();
        if (!trimmed.startsWith('$')) {
            return null;
        }

        String withoutPrefix = trimmed.substring(1);
        Integer separatorIndex = withoutPrefix.indexOf('.');
        if (separatorIndex <= 0 || separatorIndex >= withoutPrefix.length() - 1) {
            return null;
        }

        String objectApiName = withoutPrefix.substring(0, separatorIndex).trim();
        String fieldApiName = withoutPrefix.substring(separatorIndex + 1).trim();
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return null;
        }
        return new FieldReference(objectApiName, fieldApiName);
    }

    @TestVisible
    static String getFieldApiName(String fieldReference) {
        FieldReference reference = parseFieldReference(fieldReference);
        return reference == null ? null : reference.fieldApiName;
    }

    @TestVisible
    static String getObjectApiName(String fieldReference) {
        FieldReference reference = parseFieldReference(fieldReference);
        return reference == null ? null : reference.objectApiName;
    }

    @TestVisible
    static List<MappingConfig> getEffectiveInboundMappings(String configJson, String direction) {
        MappingConfiguration config = parseConfigurationSafely(configJson);
        if (normalizeDirection(direction) == DIRECTION_BOTH &&
            !config.inboundMappings.isEmpty() &&
            config.outboundMappings.isEmpty()) {
            config.outboundMappings = cloneMappings(config.inboundMappings);
        }
        return cloneMappings(config.inboundMappings);
    }

    @TestVisible
    static List<MappingConfig> getEffectiveOutboundMappings(String configJson, String direction) {
        MappingConfiguration config = parseConfigurationSafely(configJson);
        if (normalizeDirection(direction) == DIRECTION_BOTH &&
            !config.outboundMappings.isEmpty() &&
            config.inboundMappings.isEmpty()) {
            config.inboundMappings = cloneMappings(config.outboundMappings);
        }
        if (normalizeDirection(direction) == DIRECTION_BOTH &&
            !config.inboundMappings.isEmpty() &&
            config.outboundMappings.isEmpty()) {
            config.outboundMappings = cloneMappings(config.inboundMappings);
        }
        return cloneMappings(config.outboundMappings);
    }

    private static void validateDirectionalMappings(
        List<MappingConfig> mappings,
        String expectedObjectApiName,
        Boolean inboundMode,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (String.isBlank(expectedObjectApiName)) {
            throw new PublicApiIntakeServiceException('Target object API name is required for mapping validation.');
        }

        Schema.SObjectType expectedType = resolveSObjectType(expectedObjectApiName, globalDescribe);
        if (expectedType == null) {
            throw new PublicApiIntakeServiceException('Unknown target object: ' + expectedObjectApiName);
        }
        String canonicalObjectApiName = expectedType.getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = expectedType.getDescribe().fields.getMap();

        for (MappingConfig mapping : mappings) {
            FieldReference reference = parseFieldReference(mapping == null ? null : mapping.value);
            if (reference == null) {
                throw new PublicApiIntakeServiceException('Invalid field reference: ' + (mapping == null ? null : mapping.value));
            }
            if (!equalsIgnoreCase(reference.objectApiName, canonicalObjectApiName)) {
                throw new PublicApiIntakeServiceException(
                    'Field reference object does not match configured object ' + canonicalObjectApiName + ': ' +
                    mapping.value
                );
            }

            if (equalsIgnoreCase(reference.fieldApiName, 'CreatedDate')) {
                if (inboundMode) {
                    throw new PublicApiIntakeServiceException('CreatedDate cannot be used for inbound mappings.');
                }
                continue;
            }

            String resolvedFieldApiName = resolveFieldApiName(reference.fieldApiName, fieldMap);
            if (String.isBlank(resolvedFieldApiName)) {
                throw new PublicApiIntakeServiceException('Unknown field reference: ' + mapping.value);
            }

            Schema.DescribeFieldResult describe = fieldMap.get(resolvedFieldApiName).getDescribe();
            if (inboundMode && !describe.isCreateable()) {
                throw new PublicApiIntakeServiceException(
                    'Inbound mapping field is not createable: $' + canonicalObjectApiName + '.' + resolvedFieldApiName
                );
            }
            if (!inboundMode && !describe.isAccessible()) {
                throw new PublicApiIntakeServiceException(
                    'Outbound mapping field is not readable: $' + canonicalObjectApiName + '.' + resolvedFieldApiName
                );
            }
        }
    }

    private static MappingConfiguration parseConfigurationSafely(String configJson) {
        try {
            return String.isBlank(configJson) ? new MappingConfiguration() : parseConfiguration(configJson);
        } catch (Exception e) {
            return new MappingConfiguration();
        }
    }

    private static List<MappingConfig> parseMappingArray(Object rawMappings) {
        List<MappingConfig> mappings = new List<MappingConfig>();
        if (!(rawMappings instanceof List<Object>)) {
            return mappings;
        }

        for (Object entry : (List<Object>) rawMappings) {
            if (!(entry instanceof Map<String, Object>)) {
                continue;
            }
            MappingConfig mapping = fromMap((Map<String, Object>) entry);
            if (mapping != null) {
                mappings.add(mapping);
            }
        }
        return sortMappings(mappings);
    }

    private static MappingConfig fromMap(Map<String, Object> entry) {
        if (entry == null) {
            return null;
        }

        MappingConfig mapping = new MappingConfig();
        mapping.externalKey = normalizeString(entry.get('externalKey'));
        mapping.value = normalizeString(entry.get('value'));
        mapping.sortOrder = parseInteger(entry.get('sortOrder'));
        if (String.isBlank(mapping.externalKey) || String.isBlank(mapping.value)) {
            return null;
        }
        return mapping;
    }

    private static String normalizeDirection(String direction) {
        if (String.isBlank(direction)) {
            return DIRECTION_BOTH;
        }
        String normalized = direction.trim().toLowerCase();
        if (normalized == 'inbound') {
            return DIRECTION_INBOUND;
        }
        if (normalized == 'outbound') {
            return DIRECTION_OUTBOUND;
        }
        return DIRECTION_BOTH;
    }

    private static Boolean appliesToInbound(String direction) {
        String normalized = normalizeDirection(direction);
        return normalized == DIRECTION_INBOUND || normalized == DIRECTION_BOTH;
    }

    private static Boolean appliesToOutbound(String direction) {
        String normalized = normalizeDirection(direction);
        return normalized == DIRECTION_OUTBOUND || normalized == DIRECTION_BOTH;
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
        String target = objectApiName.trim().toLowerCase();
        for (String key : globalDescribe.keySet()) {
            if (key != null && key.toLowerCase() == target) {
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
        String target = requestedFieldName.trim().toLowerCase();
        for (String key : fieldMap.keySet()) {
            if (key != null && key.toLowerCase() == target) {
                return key;
            }
        }
        return null;
    }

    private static Boolean equalsIgnoreCase(String left, String right) {
        if (left == null || right == null) {
            return left == right;
        }
        return left.trim().toLowerCase() == right.trim().toLowerCase();
    }

    private static Map<String, Object> extractDataMap(Map<String, Object> payload) {
        if (payload != null &&
            payload.containsKey('data') &&
            payload.get('data') instanceof Map<String, Object>) {
            return (Map<String, Object>) payload.get('data');
        }
        return payload;
    }

    private static Object getPayloadValue(Map<String, Object> payload, Map<String, Object> data, String externalKey) {
        if (String.isBlank(externalKey)) {
            return null;
        }

        Object value = getValueByPath(data, externalKey);
        if (value != null) {
            return value;
        }

        if (payload == data) {
            return null;
        }

        return getValueByPath(payload, externalKey);
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

    private static Object normalizeInboundValue(Object rawValue, Schema.DescribeFieldResult describe) {
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
            if (typeValue == Schema.DisplayType.Email) {
                return clampEmail(stringValue, describe.getLength());
            }
            return stringValue.substring(0, describe.getLength());
        }
        return stringValue;
    }

    private static String clampEmail(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0 || value.length() <= maxLength) {
            return value;
        }

        Integer atIndex = value.indexOf('@');
        if (atIndex <= 0) {
            return value.substring(0, maxLength);
        }

        String domain = value.substring(atIndex);
        Integer maxLocalPartLength = maxLength - domain.length();
        if (maxLocalPartLength <= 0) {
            return value.substring(0, maxLength);
        }

        String localPart = value.substring(0, atIndex);
        if (localPart.length() > maxLocalPartLength) {
            localPart = localPart.substring(0, maxLocalPartLength);
        }
        return localPart + domain;
    }

    private static Object normalizeOutboundValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
        if (value instanceof Date) {
            return ((Date) value).format();
        }
        return value;
    }

    private static void applyNameSplitIfNeeded(
        SObject targetRecord,
        Map<String, Object> data,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        if (targetRecord == null || fieldMap == null || fieldMap.isEmpty()) {
            return;
        }
        if (!fieldMap.containsKey('First_Name__c') || !fieldMap.containsKey('Last_Name__c')) {
            return;
        }

        String firstName = (String) targetRecord.get('First_Name__c');
        String lastName = (String) targetRecord.get('Last_Name__c');
        String fullName = getString(data, new List<String>{ 'name', 'full_name' });

        if (String.isBlank(fullName)) {
            return;
        }
        if (String.isNotBlank(lastName)) {
            return;
        }
        if (String.isBlank(firstName)) {
            firstName = fullName;
        }

        String normalized = firstName == null ? null : firstName.trim();
        if (String.isBlank(normalized) || !normalized.contains(' ')) {
            return;
        }
        targetRecord.put('First_Name__c', getFirstName(normalized));
        targetRecord.put('Last_Name__c', getLastName(normalized));
    }

    @TestVisible
    static String getString(Map<String, Object> source, List<String> keys) {
        if (source == null || keys == null) {
            return null;
        }
        for (String key : keys) {
            if (String.isBlank(key) || !source.containsKey(key)) {
                continue;
            }
            Object rawValue = source.get(key);
            if (rawValue == null) {
                continue;
            }
            if (rawValue instanceof List<Object>) {
                List<Object> values = (List<Object>) rawValue;
                if (values.isEmpty() || values[0] == null) {
                    continue;
                }
                rawValue = values[0];
            }
            String stringValue = String.valueOf(rawValue).trim();
            if (String.isNotBlank(stringValue)) {
                return stringValue;
            }
        }
        return null;
    }

    private static String getFirstName(String fullName) {
        Integer index = fullName.indexOf(' ');
        return index <= 0 ? fullName : fullName.substring(0, index).trim();
    }

    private static String getLastName(String fullName) {
        Integer index = fullName.indexOf(' ');
        return index <= 0 ? null : fullName.substring(index + 1).trim();
    }

    private static List<MappingConfig> cloneMappings(List<MappingConfig> mappings) {
        List<MappingConfig> cloned = new List<MappingConfig>();
        if (mappings == null) {
            return cloned;
        }
        for (MappingConfig mapping : mappings) {
            if (mapping == null) {
                continue;
            }
            cloned.add(new MappingConfig(mapping.externalKey, mapping.value, mapping.sortOrder));
        }
        return sortMappings(cloned);
    }

    private static List<MappingConfig> sortMappings(List<MappingConfig> mappings) {
        mappings.sort(new MappingSortComparator());
        return mappings;
    }

    private static Integer parseInteger(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static String normalizeString(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private class MappingSortComparator implements Comparator<MappingConfig> {
        public Integer compare(MappingConfig left, MappingConfig right) {
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
