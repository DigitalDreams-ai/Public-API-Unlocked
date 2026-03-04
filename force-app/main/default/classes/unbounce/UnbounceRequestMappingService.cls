public without sharing class UnbounceRequestMappingService {
    @TestVisible
    static final String DIRECTION_INBOUND = 'Inbound';
    @TestVisible
    static final String DIRECTION_OUTBOUND = 'Outbound';
    @TestVisible
    static final String DIRECTION_BOTH = 'Both';
    @TestVisible
    static final String INTAKE_REFERENCE_PREFIX = '$intake.';

    @TestVisible
    static final List<MappingConfig> DEFAULT_INBOUND_MAPPINGS = new List<MappingConfig>{
        new MappingConfig('name', '$intake.litify_pm__First_Name__c', 10),
        new MappingConfig('first_name', '$intake.litify_pm__First_Name__c', 20),
        new MappingConfig('last_name', '$intake.litify_pm__Last_Name__c', 30),
        new MappingConfig('email', '$intake.litify_pm__Email__c', 40),
        new MappingConfig('phone_number', '$intake.litify_pm__Phone__c', 50),
        new MappingConfig('phone', '$intake.litify_pm__Phone__c', 60),
        new MappingConfig('how_can_we_help_you', '$intake.litify_pm__Description__c', 70),
        new MappingConfig('description', '$intake.litify_pm__Description__c', 80),
        new MappingConfig('page_url', '$intake.litify_pm__lit_Exact_Source__c', 90),
        new MappingConfig('utm_source', '$intake.litify_pm__UTM_Source__c', 100),
        new MappingConfig('utm_medium', '$intake.litify_pm__UTM_Medium__c', 110),
        new MappingConfig('campaignid', '$intake.litify_pm__UTM_Campaign__c', 120),
        new MappingConfig('utm_content', '$intake.litify_pm__UTM_Content__c', 130),
        new MappingConfig('gclid', '$intake.GCLID__c', 140)
    };

    @TestVisible
    static final List<MappingConfig> DEFAULT_OUTBOUND_MAPPINGS = new List<MappingConfig>{
        new MappingConfig('firstName', '$intake.litify_pm__First_Name__c', 10),
        new MappingConfig('lastName', '$intake.litify_pm__Last_Name__c', 20),
        new MappingConfig('email', '$intake.litify_pm__Email__c', 30),
        new MappingConfig('gclid', '$intake.GCLID__c', 40),
        new MappingConfig('conversionTime', '$intake.Google_Ads_Conversion_Time__c', 50),
        new MappingConfig('createdDate', '$intake.CreatedDate', 60)
    };

    public class MappingConfig {
        public String externalKey;
        public String value;
        public Integer sortOrder;

        public MappingConfig() {}

        public MappingConfig(String externalKey, String value, Integer sortOrder) {
            this.externalKey = externalKey;
            this.value = value;
            this.sortOrder = sortOrder;
        }
    }

    public class MappingConfiguration {
        public List<MappingConfig> inboundMappings = new List<MappingConfig>();
        public List<MappingConfig> outboundMappings = new List<MappingConfig>();
    }

    public static String getDefaultDirection() {
        return DIRECTION_BOTH;
    }

    public static String getDefaultMappingsJson() {
        return JSON.serializePretty(toSerializableMap(getDefaultConfiguration()));
    }

    public static List<String> getAvailableFieldReferences() {
        List<String> references = new List<String>();
        List<String> fieldNames =
            new List<String>(litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap().keySet());
        fieldNames.sort();
        for (String fieldName : fieldNames) {
            references.add(INTAKE_REFERENCE_PREFIX + fieldName);
        }
        return references;
    }

    public static void applyInboundMappings(
        litify_pm__Intake__c intake,
        Map<String, Object> payload,
        String configJson,
        String direction
    ) {
        if (intake == null || payload == null || !appliesToInbound(direction)) {
            return;
        }

        Map<String, Schema.SObjectField> intakeFields =
            litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();
        Map<String, Object> data = extractDataMap(payload);
        for (MappingConfig mapping : getEffectiveInboundMappings(configJson, direction)) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isBlank(fieldApiName) || !intakeFields.containsKey(fieldApiName)) {
                continue;
            }

            Object rawValue = getPayloadValue(payload, data, mapping.externalKey);
            if (rawValue == null) {
                continue;
            }

            try {
                intake.put(
                    fieldApiName,
                    normalizeInboundValue(mapping.externalKey, fieldApiName, rawValue, intakeFields)
                );
            } catch (Exception e) {
                continue;
            }
        }

        applyNameSplitIfNeeded(intake, data);
        applyDefaultSourceType(intake);
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

        Map<String, Schema.SObjectField> fieldMap =
            sourceRecord.getSObjectType().getDescribe().fields.getMap();
        for (MappingConfig mapping : getEffectiveOutboundMappings(configJson, direction)) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isBlank(fieldApiName)) {
                continue;
            }

            Object value;
            try {
                if (fieldMap.containsKey(fieldApiName) || fieldApiName == 'CreatedDate') {
                    value = sourceRecord.get(fieldApiName);
                } else {
                    continue;
                }
            } catch (Exception e) {
                continue;
            }

            payload.put(mapping.externalKey, normalizeOutboundValue(value));
        }
        return payload;
    }

    public static Set<String> getOutboundFieldApiNames(String configJson, String direction) {
        Set<String> fieldApiNames = new Set<String>();
        if (!appliesToOutbound(direction)) {
            return fieldApiNames;
        }

        List<MappingConfig> mappings;
        try {
            mappings = getEffectiveOutboundMappings(configJson, direction);
        } catch (Exception e) {
            mappings = cloneMappings(DEFAULT_OUTBOUND_MAPPINGS);
        }

        for (MappingConfig mapping : mappings) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isNotBlank(fieldApiName)) {
                fieldApiNames.add(fieldApiName);
            }
        }
        return fieldApiNames;
    }

    public static void validateMappings(String configJson, String direction) {
        if (String.isBlank(configJson)) {
            return;
        }

        Map<String, Schema.SObjectField> intakeFields =
            litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();
        MappingConfiguration config = parseConfiguration(configJson);
        for (MappingConfig mapping : getMappingsForValidation(config, direction)) {
            String fieldApiName = getFieldApiName(mapping.value);
            if (String.isBlank(fieldApiName) || !intakeFields.containsKey(fieldApiName)) {
                throw new UnbounceIntakeServiceException(
                    'Unknown Intake field reference: ' + mapping.value
                );
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
            throw new UnbounceIntakeServiceException(
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
    static List<MappingConfig> parseMappingsArrayJson(String mappingsJson) {
        return parseMappingArray(JSON.deserializeUntyped(mappingsJson));
    }

    @TestVisible
    static String getFieldApiName(String fieldReference) {
        if (String.isBlank(fieldReference)) {
            return null;
        }
        String trimmed = fieldReference.trim();
        if (!trimmed.startsWith(INTAKE_REFERENCE_PREFIX)) {
            return null;
        }
        String fieldApiName = trimmed.substring(INTAKE_REFERENCE_PREFIX.length());
        return String.isBlank(fieldApiName) ? null : fieldApiName;
    }

    @TestVisible
    static MappingConfiguration getDefaultConfiguration() {
        MappingConfiguration config = new MappingConfiguration();
        config.inboundMappings = cloneMappings(DEFAULT_INBOUND_MAPPINGS);
        config.outboundMappings = cloneMappings(DEFAULT_OUTBOUND_MAPPINGS);
        return config;
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
        return String.isBlank(configJson) ? new MappingConfiguration() : parseConfiguration(configJson);
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

    private static Map<String, Object> toSerializableMap(MappingConfiguration config) {
        Map<String, Object> serialized = new Map<String, Object>();
        serialized.put('inbound', cloneMappings(config == null ? null : config.inboundMappings));
        serialized.put('outbound', cloneMappings(config == null ? null : config.outboundMappings));
        return serialized;
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

    private static List<MappingConfig> getMappingsForValidation(
        MappingConfiguration config,
        String direction
    ) {
        List<MappingConfig> mappings = new List<MappingConfig>();
        if (appliesToInbound(direction)) {
            mappings.addAll(config.inboundMappings);
        }
        if (appliesToOutbound(direction)) {
            mappings.addAll(config.outboundMappings);
        }
        return mappings;
    }

    private static Boolean appliesToInbound(String direction) {
        String normalized = normalizeDirection(direction);
        return normalized == DIRECTION_INBOUND || normalized == DIRECTION_BOTH;
    }

    private static Boolean appliesToOutbound(String direction) {
        String normalized = normalizeDirection(direction);
        return normalized == DIRECTION_OUTBOUND || normalized == DIRECTION_BOTH;
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

    private static Map<String, Object> extractDataMap(Map<String, Object> payload) {
        if (payload != null &&
            payload.containsKey('data') &&
            payload.get('data') instanceof Map<String, Object>) {
            return (Map<String, Object>) payload.get('data');
        }
        return payload;
    }

    private static Object getPayloadValue(
        Map<String, Object> payload,
        Map<String, Object> data,
        String externalKey
    ) {
        if (String.isBlank(externalKey)) {
            return null;
        }

        Object value = getValueByPath(data, externalKey);
        if (value != null) {
            return value;
        }
        return payload == data ? null : getValueByPath(payload, externalKey);
    }

    private static Object getValueByPath(Map<String, Object> root, String path) {
        if (root == null || String.isBlank(path)) {
            return null;
        }

        Object current = root;
        for (String token : path.split('\\.')) {
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            current = ((Map<String, Object>) current).get(token);
            if (current == null) {
                return null;
            }
        }
        return current;
    }

    private static Object normalizeInboundValue(
        String externalKey,
        String fieldApiName,
        Object rawValue,
        Map<String, Schema.SObjectField> intakeFields
    ) {
        if (rawValue instanceof List<Object>) {
            for (Object item : (List<Object>) rawValue) {
                Object normalized = normalizeInboundValue(externalKey, fieldApiName, item, intakeFields);
                if (normalized != null) {
                    return normalized;
                }
            }
            return null;
        }

        Schema.DescribeFieldResult fieldDescribe = intakeFields.get(fieldApiName).getDescribe();
        String normalizedString = normalizeString(rawValue);
        if (normalizedString == null || isEchoedFieldToken(normalizedString, externalKey)) {
            return null;
        }

        if (fieldDescribe.getType() == Schema.DisplayType.Boolean) {
            return normalizedString.toLowerCase() == 'true';
        }
        if (fieldDescribe.getType() == Schema.DisplayType.DateTime) {
            try {
                return Datetime.valueOfGmt(normalizedString.replace('T', ' ').replace('Z', ''));
            } catch (Exception e) {
                return normalizedString;
            }
        }
        if (fieldDescribe.getType() == Schema.DisplayType.Date) {
            try {
                return Date.valueOf(normalizedString);
            } catch (Exception e) {
                return normalizedString;
            }
        }
        if (fieldDescribe.getType() == Schema.DisplayType.Double ||
            fieldDescribe.getType() == Schema.DisplayType.Currency ||
            fieldDescribe.getType() == Schema.DisplayType.Percent) {
            try {
                return Decimal.valueOf(normalizedString);
            } catch (Exception e) {
                return normalizedString;
            }
        }
        if (fieldDescribe.getType() == Schema.DisplayType.Integer) {
            try {
                return Integer.valueOf(normalizedString);
            } catch (Exception e) {
                return normalizedString;
            }
        }

        Integer maxLength = fieldDescribe.getLength();
        if (maxLength != null && maxLength > 0 && normalizedString.length() > maxLength) {
            if (fieldDescribe.getType() == Schema.DisplayType.Email) {
                return clampEmail(normalizedString, maxLength);
            }
            return normalizedString.substring(0, maxLength);
        }
        return normalizedString;
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

    private static void applyNameSplitIfNeeded(litify_pm__Intake__c intake, Map<String, Object> data) {
        String mappedFirstName = (String) intake.get('litify_pm__First_Name__c');
        String mappedLastName = (String) intake.get('litify_pm__Last_Name__c');
        if (String.isNotBlank(mappedLastName) ||
            String.isBlank(mappedFirstName) ||
            !looksLikeFullName(mappedFirstName)) {
            return;
        }

        if (data == null || !data.containsKey('name') || data.containsKey('last_name')) {
            return;
        }

        intake.put('litify_pm__First_Name__c', getFirstName(mappedFirstName));
        intake.put('litify_pm__Last_Name__c', getLastName(mappedFirstName));
    }

    private static void applyDefaultSourceType(litify_pm__Intake__c intake) {
        if (intake == null || intake.get('litify_pm__Source_Type__c') != null) {
            return;
        }

        String defaultSourceType = UnbounceIntakeModel.getDefaultSourceTypeValue();
        if (String.isNotBlank(defaultSourceType)) {
            intake.put('litify_pm__Source_Type__c', defaultSourceType);
        }
    }

    private static Boolean isEchoedFieldToken(String value, String key) {
        if (String.isBlank(value) || String.isBlank(key)) {
            return false;
        }
        return value.trim().toLowerCase() == key.trim().toLowerCase();
    }

    private static Boolean looksLikeFullName(String name) {
        return String.isNotBlank(name) && name.contains(' ');
    }

    private static String getFirstName(String fullName) {
        List<String> parts = splitName(fullName);
        return parts.isEmpty() ? fullName : parts[0];
    }

    private static String getLastName(String fullName) {
        List<String> parts = splitName(fullName);
        return parts.size() > 1 ? parts[1] : null;
    }

    private static List<String> splitName(String fullName) {
        if (String.isBlank(fullName)) {
            return new List<String>();
        }
        List<String> rawParts = fullName.trim().split('\\s+');
        if (rawParts.size() <= 1) {
            return new List<String>{ fullName.trim() };
        }

        List<String> lastNameParts = new List<String>();
        for (Integer i = 1; i < rawParts.size(); i++) {
            lastNameParts.add(rawParts[i]);
        }
        return new List<String>{ rawParts[0], String.join(lastNameParts, ' ') };
    }

    private static Integer parseInteger(Object value) {
        if (value == null) {
            return 0;
        }
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return 0;
        }
    }

    private static String normalizeString(Object value) {
        if (value == null) {
            return null;
        }
        String stringValue = String.valueOf(value);
        return String.isBlank(stringValue) ? null : stringValue.trim();
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

    private static List<MappingConfig> sortMappings(List<MappingConfig> source) {
        List<MappingConfig> sorted = cloneMappings(source);
        Integer size = sorted.size();
        for (Integer i = 0; i < size; i++) {
            Integer minIndex = i;
            for (Integer j = i + 1; j < size; j++) {
                if (comesBefore(sorted[j], sorted[minIndex])) {
                    minIndex = j;
                }
            }
            if (minIndex != i) {
                MappingConfig temp = sorted[i];
                sorted[i] = sorted[minIndex];
                sorted[minIndex] = temp;
            }
        }
        return sorted;
    }

    private static Boolean comesBefore(MappingConfig first, MappingConfig second) {
        Integer firstOrder = first == null || first.sortOrder == null ? 0 : first.sortOrder;
        Integer secondOrder = second == null || second.sortOrder == null ? 0 : second.sortOrder;
        if (firstOrder != secondOrder) {
            return firstOrder < secondOrder;
        }

        String firstKey = first == null || first.externalKey == null ? '' : first.externalKey;
        String secondKey = second == null || second.externalKey == null ? '' : second.externalKey;
        return firstKey < secondKey;
    }

    private static List<MappingConfig> cloneMappings(List<MappingConfig> source) {
        List<MappingConfig> cloned = new List<MappingConfig>();
        if (source == null) {
            return cloned;
        }
        for (MappingConfig mapping : source) {
            cloned.add(new MappingConfig(
                mapping.externalKey,
                mapping.value,
                mapping.sortOrder
            ));
        }
        return cloned;
    }
}
