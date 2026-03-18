public without sharing class PublicApiRequestMappingService {
    @TestVisible static final String DEFAULT_OBJECT_API_NAME = 'PublicApi_Submission__c';
    @TestVisible static final String SOURCE_TYPE_INCOMING_KEY = 'IncomingKey';
    @TestVisible static final String SOURCE_TYPE_LITERAL_VALUE = 'LiteralValue';

    public class MappingConfig {
        @AuraEnabled public String externalKey;
        @AuraEnabled public String value;
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String literalValue;
        @AuraEnabled public String defaultValue;

        public MappingConfig() {}

        public MappingConfig(String externalKey, String value, Integer sortOrder) {
            this(externalKey, value, sortOrder, SOURCE_TYPE_INCOMING_KEY, null, null);
        }

        public MappingConfig(
            String externalKey,
            String value,
            Integer sortOrder,
            String sourceType,
            String literalValue,
            String defaultValue
        ) {
            this.externalKey = externalKey;
            this.value = value;
            this.sortOrder = sortOrder;
            this.sourceType = normalizeSourceType(sourceType);
            this.literalValue = literalValue;
            this.defaultValue = defaultValue;
        }
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

    private class NameSplitTargets {
        public String firstNameFieldApiName;
        public String lastNameFieldApiName;
    }

    private class PayloadValueResult {
        public Boolean found;
        public Object value;

        public PayloadValueResult(Boolean found, Object value) {
            this.found = found;
            this.value = value;
        }
    }

    public static void applyInboundMappings(
        SObject targetRecord,
        Map<String, Object> payload,
        String inboundConfigJson
    ) {
        String targetObjectApiName = targetRecord == null
            ? null
            : targetRecord.getSObjectType().getDescribe().getName();
        applyInboundMappings(targetRecord, payload, inboundConfigJson, targetObjectApiName);
    }

    public static void applyInboundMappings(
        SObject targetRecord,
        Map<String, Object> payload,
        String inboundConfigJson,
        String targetObjectApiName
    ) {
        if (targetRecord == null || payload == null) {
            return;
        }

        String recordObjectApiName = targetRecord.getSObjectType().getDescribe().getName();
        String expectedObjectApiName = String.isBlank(targetObjectApiName)
            ? recordObjectApiName
            : targetObjectApiName.trim();
        if (!equalsIgnoreCase(recordObjectApiName, expectedObjectApiName)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = targetRecord.getSObjectType().getDescribe().fields.getMap();
        Map<String, Object> data = extractDataMap(payload);
        List<MappingConfig> inboundMappings = parseMappings(inboundConfigJson);
        for (MappingConfig mapping : inboundMappings) {
            FieldReference reference = parseFieldReference(mapping == null ? null : mapping.value);
            if (reference == null || !equalsIgnoreCase(reference.objectApiName, recordObjectApiName)) {
                continue;
            }

            String resolvedFieldApiName = resolveFieldApiName(reference.fieldApiName, fieldMap);
            if (String.isBlank(resolvedFieldApiName)) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(resolvedFieldApiName).getDescribe();
            Object rawValue = resolveInboundRawValue(mapping, payload, data);
            if (rawValue == null) {
                continue;
            }

            try {
                targetRecord.put(
                    resolvedFieldApiName,
                    normalizeInboundValue(
                        rawValue,
                        fieldDescribe,
                        normalizeSourceType(mapping == null ? null : mapping.sourceType) == SOURCE_TYPE_LITERAL_VALUE
                    )
                );
            } catch (PublicApiSubmissionServiceException e) {
                throw e;
            } catch (Exception e) {
                continue;
            }
        }

        applyNameSplitIfNeeded(targetRecord, data, fieldMap, inboundMappings, recordObjectApiName);
    }

    public static Map<String, Object> buildOutboundPayload(SObject sourceRecord, String outboundConfigJson) {
        String sourceObjectApiName = sourceRecord == null
            ? null
            : sourceRecord.getSObjectType().getDescribe().getName();
        return buildOutboundPayload(sourceRecord, outboundConfigJson, sourceObjectApiName);
    }

    public static Map<String, Object> buildOutboundPayload(
        SObject sourceRecord,
        String outboundConfigJson,
        String sourceObjectApiName
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        if (sourceRecord == null) {
            return payload;
        }

        String recordObjectApiName = sourceRecord.getSObjectType().getDescribe().getName();
        if (String.isNotBlank(sourceObjectApiName) &&
            !equalsIgnoreCase(recordObjectApiName, sourceObjectApiName)) {
            return payload;
        }

        Map<String, Schema.SObjectField> fieldMap = sourceRecord.getSObjectType().getDescribe().fields.getMap();
        for (MappingConfig mapping : parseMappings(outboundConfigJson)) {
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

    public static Set<String> getOutboundFieldApiNames(String outboundConfigJson) {
        return getOutboundFieldApiNames(outboundConfigJson, DEFAULT_OBJECT_API_NAME);
    }

    public static Set<String> getOutboundFieldApiNames(
        String outboundConfigJson,
        String sourceObjectApiName
    ) {
        Set<String> fieldApiNames = new Set<String>();
        if (String.isBlank(sourceObjectApiName)) {
            return fieldApiNames;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objectType = resolveSObjectType(sourceObjectApiName, globalDescribe);
        if (objectType == null) {
            return fieldApiNames;
        }

        String canonicalObjectApiName = objectType.getDescribe().getName();
        Map<String, Schema.SObjectField> validFields = objectType.getDescribe().fields.getMap();
        for (MappingConfig mapping : parseMappings(outboundConfigJson)) {
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

    public static void validateInboundMappings(String inboundConfigJson) {
        validateInboundMappings(inboundConfigJson, DEFAULT_OBJECT_API_NAME);
    }

    public static void validateInboundMappings(String inboundConfigJson, String targetObjectApiName) {
        validateDirectionalMappings(inboundConfigJson, targetObjectApiName, true);
    }

    public static void validateOutboundMappings(String outboundConfigJson) {
        validateOutboundMappings(outboundConfigJson, DEFAULT_OBJECT_API_NAME);
    }

    public static void validateOutboundMappings(String outboundConfigJson, String sourceObjectApiName) {
        validateDirectionalMappings(outboundConfigJson, sourceObjectApiName, false);
    }

    public static List<MappingConfig> parseMappings(String configJson) {
        List<MappingConfig> mappings = new List<MappingConfig>();
        if (String.isBlank(configJson)) {
            return mappings;
        }

        Object parsed = JSON.deserializeUntyped(configJson);
        if (!(parsed instanceof List<Object>)) {
            throw new PublicApiSubmissionServiceException(
                'Mapping configuration must be a JSON array of mapping rows.'
            );
        }

        for (Object entry : (List<Object>) parsed) {
            if (!(entry instanceof Map<String, Object>)) {
                continue;
            }
            MappingConfig mapping = fromMap((Map<String, Object>) entry);
            if (mapping != null) {
                mappings.add(mapping);
            }
        }
        mappings.sort(new MappingSortComparator());
        return mappings;
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

    private static void validateDirectionalMappings(
        String configJson,
        String expectedObjectApiName,
        Boolean inboundMode
    ) {
        if (String.isBlank(expectedObjectApiName)) {
            throw new PublicApiSubmissionServiceException('Target object API name is required for mapping validation.');
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType expectedType = resolveSObjectType(expectedObjectApiName, globalDescribe);
        if (expectedType == null) {
            throw new PublicApiSubmissionServiceException('Unknown target object: ' + expectedObjectApiName);
        }

        String canonicalObjectApiName = expectedType.getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = expectedType.getDescribe().fields.getMap();
        for (MappingConfig mapping : parseMappings(configJson)) {
            if (inboundMode &&
                normalizeSourceType(mapping == null ? null : mapping.sourceType) == SOURCE_TYPE_INCOMING_KEY &&
                String.isBlank(mapping == null ? null : mapping.externalKey)) {
                throw new PublicApiSubmissionServiceException('Inbound mapping external key is required.');
            }
            FieldReference reference = parseFieldReference(mapping == null ? null : mapping.value);
            if (reference == null) {
                throw new PublicApiSubmissionServiceException(
                    'Invalid field reference: ' + (mapping == null ? null : mapping.value)
                );
            }
            if (!equalsIgnoreCase(reference.objectApiName, canonicalObjectApiName)) {
                throw new PublicApiSubmissionServiceException(
                    'Field reference object does not match configured object ' + canonicalObjectApiName + ': ' +
                    mapping.value
                );
            }

            if (equalsIgnoreCase(reference.fieldApiName, 'CreatedDate')) {
                if (inboundMode) {
                    throw new PublicApiSubmissionServiceException('CreatedDate cannot be used for inbound mappings.');
                }
                continue;
            }

            String resolvedFieldApiName = resolveFieldApiName(reference.fieldApiName, fieldMap);
            if (String.isBlank(resolvedFieldApiName)) {
                throw new PublicApiSubmissionServiceException('Unknown field reference: ' + mapping.value);
            }

            Schema.DescribeFieldResult describe = fieldMap.get(resolvedFieldApiName).getDescribe();
            if (inboundMode && !isStructurallyWritableField(describe)) {
                throw new PublicApiSubmissionServiceException(
                    'Inbound mapping field is read-only: $' + canonicalObjectApiName + '.' + resolvedFieldApiName
                );
            }
            if (!inboundMode && !isStructurallyReadableField(describe)) {
                throw new PublicApiSubmissionServiceException(
                    'Outbound mapping field is not readable: $' + canonicalObjectApiName + '.' + resolvedFieldApiName
                );
            }
        }
    }

    private static MappingConfig fromMap(Map<String, Object> entry) {
        if (entry == null) {
            return null;
        }

        MappingConfig mapping = new MappingConfig();
        mapping.externalKey = normalizeString(entry.get('externalKey'));
        mapping.value = normalizeString(entry.get('value'));
        mapping.sortOrder = parseInteger(entry.get('sortOrder'));
        mapping.sourceType = normalizeSourceType(normalizeString(entry.get('sourceType')));
        mapping.literalValue = normalizeString(entry.get('literalValue'));
        mapping.defaultValue = normalizeString(entry.get('defaultValue'));
        if (String.isBlank(mapping.value)) {
            return null;
        }
        if (mapping.sourceType == SOURCE_TYPE_INCOMING_KEY && String.isBlank(mapping.externalKey)) {
            return null;
        }
        return mapping;
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

    @TestVisible
    private static Boolean isStructurallyWritableField(Schema.DescribeFieldResult describe) {
        if (describe == null || describe.isCalculated() || describe.isAutoNumber()) {
            return false;
        }

        Schema.DisplayType fieldType = describe.getType();
        return fieldType != Schema.DisplayType.Address &&
            fieldType != Schema.DisplayType.Location;
    }

    @TestVisible
    private static Boolean isStructurallyReadableField(Schema.DescribeFieldResult describe) {
        if (describe == null) {
            return false;
        }

        Schema.DisplayType fieldType = describe.getType();
        return fieldType != Schema.DisplayType.Address &&
            fieldType != Schema.DisplayType.Location;
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

    private static Object resolveInboundRawValue(
        MappingConfig mapping,
        Map<String, Object> payload,
        Map<String, Object> data
    ) {
        if (mapping == null) {
            return null;
        }
        if (normalizeSourceType(mapping.sourceType) == SOURCE_TYPE_LITERAL_VALUE) {
            return mapping.literalValue;
        }

        PayloadValueResult payloadValue = getPayloadValue(payload, data, mapping.externalKey);
        if (payloadValue.found) {
            return payloadValue.value;
        }
        return null;
    }

    private static PayloadValueResult getPayloadValue(
        Map<String, Object> payload,
        Map<String, Object> data,
        String externalKey
    ) {
        if (String.isBlank(externalKey)) {
            return new PayloadValueResult(false, null);
        }

        PayloadValueResult value = getValueByPath(data, externalKey);
        if (value.found) {
            return value;
        }

        if (payload == data) {
            return new PayloadValueResult(false, null);
        }

        return getValueByPath(payload, externalKey);
    }

    private static PayloadValueResult getValueByPath(Map<String, Object> root, String path) {
        if (root == null || String.isBlank(path)) {
            return new PayloadValueResult(false, null);
        }
        if (root.containsKey(path)) {
            return new PayloadValueResult(true, root.get(path));
        }

        Object current = root;
        for (String token : path.split('\\.')) {
            if (!(current instanceof Map<String, Object>)) {
                return new PayloadValueResult(false, null);
            }
            Map<String, Object> currentMap = (Map<String, Object>) current;
            if (!currentMap.containsKey(token)) {
                return new PayloadValueResult(false, null);
            }
            current = currentMap.get(token);
        }
        return new PayloadValueResult(true, current);
    }

    private static Object normalizeInboundValue(
        Object rawValue,
        Schema.DescribeFieldResult describe,
        Boolean allowLiteralLookupResolution
    ) {
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
        if (typeValue == Schema.DisplayType.Reference) {
            return normalizeReferenceInboundValue(stringValue, describe, allowLiteralLookupResolution);
        }
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

    private static Object normalizeReferenceInboundValue(
        String stringValue,
        Schema.DescribeFieldResult describe,
        Boolean allowLiteralLookupResolution
    ) {
        if (String.isBlank(stringValue)) {
            return null;
        }
        if (looksLikeSalesforceId(stringValue) || allowLiteralLookupResolution != true) {
            return stringValue;
        }

        List<Schema.SObjectType> referenceTypes = describe.getReferenceTo();
        if (referenceTypes == null || referenceTypes.size() != 1 || referenceTypes[0] == null) {
            return stringValue;
        }

        Schema.DescribeSObjectResult relatedDescribe = referenceTypes[0].getDescribe();
        Map<String, Schema.SObjectField> relatedFieldMap = relatedDescribe.fields.getMap();
        if (!relatedFieldMap.containsKey('Name')) {
            return stringValue;
        }

        String relatedObjectApiName = relatedDescribe.getName();
        List<SObject> matches = Database.query(
            'SELECT Id FROM ' + relatedObjectApiName + ' WHERE Name = :stringValue LIMIT 2'
        );
        if (matches.isEmpty()) {
            throw new PublicApiSubmissionServiceException(
                'Lookup literal value "' + stringValue + '" did not match any ' +
                relatedObjectApiName + ' records by Name for field ' + describe.getName() + '.'
            );
        }
        if (matches.size() > 1) {
            throw new PublicApiSubmissionServiceException(
                'Lookup literal value "' + stringValue + '" matched multiple ' +
                relatedObjectApiName + ' records by Name for field ' + describe.getName() + '.'
            );
        }
        return matches[0].Id;
    }

    @TestVisible
    static Boolean looksLikeSalesforceId(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String trimmed = value.trim();
        if (trimmed.length() != 15 && trimmed.length() != 18) {
            return false;
        }
        return Pattern.matches('[a-zA-Z0-9]+', trimmed);
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
        Map<String, Schema.SObjectField> fieldMap,
        List<MappingConfig> inboundMappings,
        String recordObjectApiName
    ) {
        if (targetRecord == null || fieldMap == null || fieldMap.isEmpty()) {
            return;
        }

        NameSplitTargets targets = resolveNameSplitTargets(inboundMappings, recordObjectApiName, fieldMap);
        if (targets == null ||
            String.isBlank(targets.firstNameFieldApiName) ||
            String.isBlank(targets.lastNameFieldApiName)) {
            return;
        }

        String firstName = stringifySObjectValue(targetRecord.get(targets.firstNameFieldApiName));
        String lastName = stringifySObjectValue(targetRecord.get(targets.lastNameFieldApiName));
        String fullName = getString(data, new List<String>{ 'name', 'full_name' });

        if (String.isBlank(fullName) || String.isNotBlank(lastName)) {
            return;
        }
        if (String.isBlank(firstName)) {
            firstName = fullName;
        }

        String normalizedFirstName = firstName == null ? null : firstName.trim();
        if (String.isBlank(normalizedFirstName) || !normalizedFirstName.contains(' ')) {
            return;
        }

        targetRecord.put(targets.firstNameFieldApiName, getFirstName(normalizedFirstName));
        targetRecord.put(targets.lastNameFieldApiName, getLastName(normalizedFirstName));
    }

    private static NameSplitTargets resolveNameSplitTargets(
        List<MappingConfig> inboundMappings,
        String recordObjectApiName,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        if (inboundMappings == null || inboundMappings.isEmpty() || String.isBlank(recordObjectApiName)) {
            return null;
        }

        NameSplitTargets targets = new NameSplitTargets();
        for (MappingConfig mapping : inboundMappings) {
            if (mapping == null || String.isBlank(mapping.externalKey)) {
                continue;
            }

            FieldReference reference = parseFieldReference(mapping.value);
            if (reference == null || !equalsIgnoreCase(reference.objectApiName, recordObjectApiName)) {
                continue;
            }

            String resolvedFieldApiName = resolveFieldApiName(reference.fieldApiName, fieldMap);
            if (String.isBlank(resolvedFieldApiName)) {
                continue;
            }

            String normalizedExternalKey = normalizeMappingKey(mapping.externalKey);
            String normalizedFieldApiName = normalizeMappingKey(resolvedFieldApiName);
            if (isFirstNameExternalKey(normalizedExternalKey) ||
                (isFullNameExternalKey(normalizedExternalKey) && isLikelyFirstNameField(normalizedFieldApiName))) {
                targets.firstNameFieldApiName = resolvedFieldApiName;
            } else if (isLastNameExternalKey(normalizedExternalKey) ||
                (isFullNameExternalKey(normalizedExternalKey) && isLikelyLastNameField(normalizedFieldApiName))) {
                targets.lastNameFieldApiName = resolvedFieldApiName;
            }
        }

        if (String.isBlank(targets.firstNameFieldApiName) || String.isBlank(targets.lastNameFieldApiName)) {
            for (String fieldApiName : fieldMap.keySet()) {
                String normalizedFieldApiName = normalizeMappingKey(fieldApiName);
                if (String.isBlank(targets.firstNameFieldApiName) && isLikelyFirstNameField(normalizedFieldApiName)) {
                    targets.firstNameFieldApiName = fieldApiName;
                }
                if (String.isBlank(targets.lastNameFieldApiName) && isLikelyLastNameField(normalizedFieldApiName)) {
                    targets.lastNameFieldApiName = fieldApiName;
                }
            }
        }

        if (String.isBlank(targets.firstNameFieldApiName) || String.isBlank(targets.lastNameFieldApiName)) {
            return null;
        }
        return targets;
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

    private static String stringifySObjectValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String normalizeMappingKey(String value) {
        return String.isBlank(value) ? null : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    private static Boolean isFirstNameExternalKey(String normalizedExternalKey) {
        return normalizedExternalKey == 'firstname';
    }

    private static Boolean isLastNameExternalKey(String normalizedExternalKey) {
        return normalizedExternalKey == 'lastname';
    }

    private static Boolean isFullNameExternalKey(String normalizedExternalKey) {
        return normalizedExternalKey == 'name' || normalizedExternalKey == 'fullname';
    }

    private static Boolean isLikelyFirstNameField(String normalizedFieldApiName) {
        return String.isNotBlank(normalizedFieldApiName) && normalizedFieldApiName.contains('firstname');
    }

    private static Boolean isLikelyLastNameField(String normalizedFieldApiName) {
        return String.isNotBlank(normalizedFieldApiName) && normalizedFieldApiName.contains('lastname');
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

    private static String normalizeSourceType(String sourceType) {
        return String.isNotBlank(sourceType) &&
            sourceType.toLowerCase() == SOURCE_TYPE_LITERAL_VALUE.toLowerCase()
            ? SOURCE_TYPE_LITERAL_VALUE
            : SOURCE_TYPE_INCOMING_KEY;
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

