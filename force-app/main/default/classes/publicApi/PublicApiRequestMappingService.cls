public without sharing class PublicApiRequestMappingService {
    @TestVisible static final String DIRECTION_INBOUND = 'Inbound';
    @TestVisible static final String DIRECTION_OUTBOUND = 'Outbound';
    @TestVisible static final String DIRECTION_BOTH = 'Both';
    @TestVisible static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';
    @TestVisible static final String RECORD_REFERENCE_PREFIX = '$intakes.';

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

    @TestVisible
    static final List<MappingConfig> DEFAULT_INBOUND_MAPPINGS = new List<MappingConfig>{
        new MappingConfig('name', '$intakes.First_Name__c', 10),
        new MappingConfig('first_name', '$intakes.First_Name__c', 20),
        new MappingConfig('last_name', '$intakes.Last_Name__c', 30),
        new MappingConfig('email', '$intakes.Email__c', 40),
        new MappingConfig('phone_number', '$intakes.Phone__c', 50),
        new MappingConfig('phone', '$intakes.Phone__c', 60),
        new MappingConfig('how_can_we_help_you', '$intakes.Description__c', 70),
        new MappingConfig('description', '$intakes.Description__c', 80),
        new MappingConfig('page_url', '$intakes.Page_URL__c', 90),
        new MappingConfig('utm_source', '$intakes.UTM_Source__c', 100),
        new MappingConfig('utm_medium', '$intakes.UTM_Medium__c', 110),
        new MappingConfig('campaignid', '$intakes.Campaign_Id__c', 120),
        new MappingConfig('utm_content', '$intakes.UTM_Content__c', 130),
        new MappingConfig('gclid', '$intakes.GCLID__c', 140)
    };

    @TestVisible
    static final List<MappingConfig> DEFAULT_OUTBOUND_MAPPINGS = new List<MappingConfig>{
        new MappingConfig('name', '$intakes.First_Name__c', 10),
        new MappingConfig('last_name', '$intakes.Last_Name__c', 20),
        new MappingConfig('email', '$intakes.Email__c', 30),
        new MappingConfig('phone', '$intakes.Phone__c', 40),
        new MappingConfig('gclid', '$intakes.GCLID__c', 50),
        new MappingConfig('createdDate', '$intakes.CreatedDate', 60)
    };

    public static String getDefaultDirection() {
        return DIRECTION_BOTH;
    }

    public static String getDefaultMappingsJson() {
        return JSON.serializePretty(toSerializableMap(getDefaultConfiguration()));
    }

    public static List<String> getAvailableFieldReferences() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(SUBMISSION_OBJECT_API_NAME)) {
            return new List<String>();
        }

        List<String> references = new List<String>();
        Map<String, Schema.SObjectField> fieldMap =
            globalDescribe.get(SUBMISSION_OBJECT_API_NAME).getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>(fieldMap.keySet());
        fieldNames.sort();
        for (String fieldName : fieldNames) {
            references.add(RECORD_REFERENCE_PREFIX + fieldName);
        }
        references.add(RECORD_REFERENCE_PREFIX + 'CreatedDate');
        return references;
    }

    public static void applyInboundMappings(
        SObject submission,
        Map<String, Object> payload,
        String configJson,
        String direction
    ) {
        if (submission == null || payload == null || !appliesToInbound(direction)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = submission.getSObjectType().getDescribe().fields.getMap();
        Map<String, Object> data = extractDataMap(payload);
        for (MappingConfig mapping : getEffectiveInboundMappings(configJson, direction)) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isBlank(fieldApiName) || !fieldMap.containsKey(fieldApiName)) {
                continue;
            }

            Object rawValue = getPayloadValue(payload, data, mapping.externalKey);
            if (rawValue == null) {
                continue;
            }

            try {
                submission.put(fieldApiName, normalizeInboundValue(rawValue, fieldMap.get(fieldApiName).getDescribe()));
            } catch (Exception e) {
                continue;
            }
        }

        applyNameSplitIfNeeded(submission, data);
    }

    public static Map<String, Object> buildOutboundPayload(
        SObject sourceRecord,
        String configJson,
        String direction
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        if (sourceRecord == null || !appliesToOutbound(direction)) {
            return payload;
        }

        Map<String, Schema.SObjectField> fieldMap = sourceRecord.getSObjectType().getDescribe().fields.getMap();
        for (MappingConfig mapping : getEffectiveOutboundMappings(configJson, direction)) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isBlank(fieldApiName)) {
                continue;
            }

            if (fieldApiName != 'CreatedDate' && !fieldMap.containsKey(fieldApiName)) {
                continue;
            }

            try {
                payload.put(mapping.externalKey, normalizeOutboundValue(sourceRecord.get(fieldApiName)));
            } catch (Exception e) {
                continue;
            }
        }
        return payload;
    }

    public static Set<String> getOutboundFieldApiNames(String configJson, String direction) {
        Set<String> fieldApiNames = new Set<String>();
        if (!appliesToOutbound(direction)) {
            return fieldApiNames;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Map<String, Schema.SObjectField> validFields = new Map<String, Schema.SObjectField>();
        if (globalDescribe.containsKey(SUBMISSION_OBJECT_API_NAME)) {
            validFields = globalDescribe.get(SUBMISSION_OBJECT_API_NAME).getDescribe().fields.getMap();
        }

        for (MappingConfig mapping : getEffectiveOutboundMappings(configJson, direction)) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isBlank(fieldApiName)) {
                continue;
            }
            if (fieldApiName == 'CreatedDate' || validFields.containsKey(fieldApiName)) {
                fieldApiNames.add(fieldApiName);
            }
        }
        return fieldApiNames;
    }

    public static void validateMappings(String configJson, String direction) {
        if (String.isBlank(configJson)) {
            return;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(SUBMISSION_OBJECT_API_NAME)) {
            throw new PublicApiIntakeServiceException('Submission object not found: ' + SUBMISSION_OBJECT_API_NAME);
        }
        Map<String, Schema.SObjectField> fieldMap =
            globalDescribe.get(SUBMISSION_OBJECT_API_NAME).getDescribe().fields.getMap();

        MappingConfiguration config = parseConfiguration(configJson);
        for (MappingConfig mapping : getMappingsForValidation(config, direction)) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isBlank(fieldApiName)) {
                throw new PublicApiIntakeServiceException('Invalid field reference: ' + mapping.value);
            }
            if (fieldApiName != 'CreatedDate' && !fieldMap.containsKey(fieldApiName)) {
                throw new PublicApiIntakeServiceException('Unknown field reference: ' + mapping.value);
            }
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
    static String getFieldApiName(String fieldReference) {
        if (String.isBlank(fieldReference)) {
            return null;
        }
        String trimmed = fieldReference.trim();
        if (trimmed.toLowerCase().startsWith(RECORD_REFERENCE_PREFIX)) {
            return trimmed.substring(RECORD_REFERENCE_PREFIX.length());
        }
        return null;
    }

    @TestVisible
    static List<MappingConfig> getEffectiveInboundMappings(String configJson, String direction) {
        MappingConfiguration config = parseConfigurationSafely(configJson);
        if (normalizeDirection(direction) == DIRECTION_BOTH && !config.inboundMappings.isEmpty() && config.outboundMappings.isEmpty()) {
            config.outboundMappings = cloneMappings(config.inboundMappings);
        }
        return config.inboundMappings.isEmpty()
            ? cloneMappings(DEFAULT_INBOUND_MAPPINGS)
            : cloneMappings(config.inboundMappings);
    }

    @TestVisible
    static List<MappingConfig> getEffectiveOutboundMappings(String configJson, String direction) {
        MappingConfiguration config = parseConfigurationSafely(configJson);
        if (normalizeDirection(direction) == DIRECTION_BOTH && !config.outboundMappings.isEmpty() && config.inboundMappings.isEmpty()) {
            config.inboundMappings = cloneMappings(config.outboundMappings);
        }
        if (normalizeDirection(direction) == DIRECTION_BOTH && !config.inboundMappings.isEmpty() && config.outboundMappings.isEmpty()) {
            config.outboundMappings = cloneMappings(config.inboundMappings);
        }
        return config.outboundMappings.isEmpty()
            ? cloneMappings(DEFAULT_OUTBOUND_MAPPINGS)
            : cloneMappings(config.outboundMappings);
    }

    private static MappingConfiguration parseConfigurationSafely(String configJson) {
        try {
            return String.isBlank(configJson) ? new MappingConfiguration() : parseConfiguration(configJson);
        } catch (Exception e) {
            return new MappingConfiguration();
        }
    }

    private static MappingConfiguration getDefaultConfiguration() {
        MappingConfiguration config = new MappingConfiguration();
        config.inboundMappings = cloneMappings(DEFAULT_INBOUND_MAPPINGS);
        config.outboundMappings = cloneMappings(DEFAULT_OUTBOUND_MAPPINGS);
        return config;
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

    private static List<MappingConfig> getMappingsForValidation(MappingConfiguration config, String direction) {
        List<MappingConfig> mappings = new List<MappingConfig>();
        if (appliesToInbound(direction)) {
            mappings.addAll(config.inboundMappings);
        }
        if (appliesToOutbound(direction)) {
            mappings.addAll(config.outboundMappings);
        }
        return mappings;
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

    private static void applyNameSplitIfNeeded(SObject submission, Map<String, Object> data) {
        if (submission == null) {
            return;
        }
        String firstName = (String) submission.get('First_Name__c');
        String lastName = (String) submission.get('Last_Name__c');
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
        submission.put('First_Name__c', getFirstName(normalized));
        submission.put('Last_Name__c', getLastName(normalized));
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

    private static Map<String, Object> toSerializableMap(MappingConfiguration config) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('inbound', cloneMappings(config == null ? null : config.inboundMappings));
        payload.put('outbound', cloneMappings(config == null ? null : config.outboundMappings));
        return payload;
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
