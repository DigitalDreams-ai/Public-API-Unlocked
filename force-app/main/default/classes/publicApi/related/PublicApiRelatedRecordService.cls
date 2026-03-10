public without sharing class PublicApiRelatedRecordService {
    @TestVisible static final Set<String> MULTI_MATCH_POLICIES =
        new Set<String>{ 'Error', 'UseOldest', 'UseNewest' };
    @TestVisible static final String DEFAULT_MULTI_MATCH_POLICY = 'Error';

    public static void applyRelatedRecordRules(
        SObject targetRecord,
        Map<String, Object> payload,
        String relatedRecordConfigurationJson
    ) {
        if (targetRecord == null || payload == null || String.isBlank(relatedRecordConfigurationJson)) {
            return;
        }

        Map<String, Object> data = extractDataMap(payload);
        for (PublicApiRelatedRecordConfig.Rule rule :
            PublicApiRelatedRecordConfig.parseRules(relatedRecordConfigurationJson)) {
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

        List<PublicApiRelatedRecordConfig.Rule> parsedRules =
            PublicApiRelatedRecordConfig.parseRules(relatedRecordConfigurationJson);
        Map<String, Schema.SObjectField> targetFieldMap = targetObjectType.getDescribe().fields.getMap();
        for (PublicApiRelatedRecordConfig.Rule rule : parsedRules) {
            validateRule(rule, targetObjectType.getDescribe().getName(), targetFieldMap, globalDescribe);
        }
        validateCrossRuleConstraints(parsedRules, targetObjectType.getDescribe().getName());
    }

    @TestVisible
    static Set<String> getConfiguredSourceKeys(String relatedRecordConfigurationJson) {
        return PublicApiRelatedRecordConfig.getConfiguredSourceKeys(relatedRecordConfigurationJson);
    }

    public static String getImmediateRulesJson(String relatedRecordConfigurationJson) {
        return PublicApiRelatedRecordConfig.serializeRules(
            filterRulesByDeferredMode(relatedRecordConfigurationJson, false)
        );
    }

    public static String getDeferredRulesJson(String relatedRecordConfigurationJson) {
        return PublicApiRelatedRecordConfig.serializeRules(
            filterRulesByDeferredMode(relatedRecordConfigurationJson, true)
        );
    }

    @TestVisible
    static Boolean hasDeferredRules(String relatedRecordConfigurationJson) {
        return !filterRulesByDeferredMode(relatedRecordConfigurationJson, true).isEmpty();
    }

    private class ResolvedRule {
        public String targetLookupFieldApiName;
        public String relatedObjectApiName;
        public String matchFieldApiName;
        public String sourceKey;
        public Boolean createIfMissing;
        public String multiMatchPolicy;
        public List<PublicApiRelatedRecordConfig.CreateFieldMapping> createMappings;
        public Schema.DescribeFieldResult matchFieldDescribe;
        public Map<String, Schema.SObjectField> relatedFieldMap;
    }

    @TestVisible
    private static List<PublicApiRelatedRecordConfig.Rule> filterRulesByDeferredMode(
        String relatedRecordConfigurationJson,
        Boolean deferred
    ) {
        List<PublicApiRelatedRecordConfig.Rule> filteredRules = new List<PublicApiRelatedRecordConfig.Rule>();
        for (PublicApiRelatedRecordConfig.Rule rule :
            PublicApiRelatedRecordConfig.parseRules(relatedRecordConfigurationJson)) {
            if (rule == null) {
                continue;
            }
            if (shouldDeferRule(rule) == deferred) {
                filteredRules.add(rule);
            }
        }
        return filteredRules;
    }

    @TestVisible
    private static Boolean shouldDeferRule(PublicApiRelatedRecordConfig.Rule rule) {
        return rule != null &&
            String.isNotBlank(rule.relatedObjectApiName) &&
            rule.relatedObjectApiName.trim().equalsIgnoreCase('Account');
    }

    @TestVisible
    private static void validateCrossRuleConstraints(
        List<PublicApiRelatedRecordConfig.Rule> rules,
        String targetObjectApiName
    ) {
        if (rules == null || rules.isEmpty() || !isActivityObject(targetObjectApiName)) {
            return;
        }

        Boolean hasLeadWhoRule = false;
        Boolean hasAccountWhatRule = false;
        for (PublicApiRelatedRecordConfig.Rule rule : rules) {
            if (rule == null) {
                continue;
            }

            String targetLookupField = String.isBlank(rule.targetLookupField)
                ? null
                : rule.targetLookupField.trim().toLowerCase();
            String relatedObjectName = String.isBlank(rule.relatedObjectApiName)
                ? null
                : rule.relatedObjectApiName.trim().toLowerCase();

            if (targetLookupField == 'whoid' && relatedObjectName == 'lead') {
                hasLeadWhoRule = true;
            }
            if (targetLookupField == 'whatid' && relatedObjectName == 'account') {
                hasAccountWhatRule = true;
            }
        }

        if (hasLeadWhoRule && hasAccountWhatRule) {
            throw new PublicApiIntakeServiceException(
                'Task/Event related-record configuration cannot combine Lead on WhoId with Account on WhatId.'
            );
        }
    }

    @TestVisible
    private static Boolean isActivityObject(String targetObjectApiName) {
        if (String.isBlank(targetObjectApiName)) {
            return false;
        }
        String normalizedObjectName = targetObjectApiName.trim().toLowerCase();
        return normalizedObjectName == 'task' || normalizedObjectName == 'event';
    }

    private static void validateRule(
        PublicApiRelatedRecordConfig.Rule rule,
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
        if (!isStructurallyWritableField(lookupDescribe)) {
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
        if (!isStructurallyQueryableField(matchDescribe)) {
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
            for (PublicApiRelatedRecordConfig.CreateFieldMapping mapping : rule.createMappings) {
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
                if (!isStructurallyWritableField(createDescribe)) {
                    throw new PublicApiIntakeServiceException(
                        'Related record create field is read-only: ' + canonicalRelatedObjectApiName + '.' +
                        resolvedCreateFieldApiName
                    );
                }
            }
        }
    }

    private static ResolvedRule resolveRule(PublicApiRelatedRecordConfig.Rule rule, SObject targetRecord) {
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
            ? new List<PublicApiRelatedRecordConfig.CreateFieldMapping>()
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
        PublicApiRecordTypeService.applyDefaultRelatedRecordType(relatedRecord);
        Set<String> assignedFieldApiNames = new Set<String>();
        for (PublicApiRelatedRecordConfig.CreateFieldMapping mapping : rule.createMappings) {
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

        applyRequiredFieldFallbacks(relatedRecord, rule, payload, data, rawMatchValue);
        if (!assignedFieldApiNames.contains(rule.matchFieldApiName) &&
            isStructurallyWritableField(rule.matchFieldDescribe) &&
            isMissingValue(safeGetFieldValue(relatedRecord, rule.matchFieldApiName))) {
            Object normalizedMatchValue = normalizeValueForField(rawMatchValue, rule.matchFieldDescribe);
            if (normalizedMatchValue != null) {
                relatedRecord.put(rule.matchFieldApiName, normalizedMatchValue);
            }
        }
        List<String> missingRequiredFields = getMissingRequiredCreateFields(relatedRecord, rule.relatedFieldMap);
        if (!missingRequiredFields.isEmpty()) {
            throw new PublicApiIntakeServiceException(
                'Related record create configuration cannot satisfy required fields on ' +
                rule.relatedObjectApiName + ': ' + String.join(missingRequiredFields, ', ')
            );
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

    @TestVisible
    private static void applyRequiredFieldFallbacks(
        SObject relatedRecord,
        ResolvedRule rule,
        Map<String, Object> payload,
        Map<String, Object> data,
        Object rawMatchValue
    ) {
        if (relatedRecord == null || rule == null || rule.relatedFieldMap == null || rule.relatedFieldMap.isEmpty()) {
            return;
        }

        applyAccountNameFallbacks(relatedRecord, rule.relatedFieldMap, payload, data, rawMatchValue);

        String nameFieldApiName = resolveFieldApiName('Name', rule.relatedFieldMap);
        if (String.isNotBlank(nameFieldApiName)) {
            Schema.DescribeFieldResult nameDescribe = rule.relatedFieldMap.get(nameFieldApiName).getDescribe();
            if (!isDirectlyAssignableNameField(relatedRecord, rule.relatedFieldMap) ||
                !isRequiredCreateField(nameDescribe) ||
                !isMissingValue(safeGetFieldValue(relatedRecord, nameFieldApiName))) {
                return;
            }

            String derivedName = deriveRequiredNameValue(payload, data, rawMatchValue);
            if (String.isNotBlank(derivedName)) {
                relatedRecord.put(
                    nameFieldApiName,
                    normalizeValueForField(derivedName, nameDescribe)
                );
            }
        }
    }

    @TestVisible
    private static void applyAccountNameFallbacks(
        SObject relatedRecord,
        Map<String, Schema.SObjectField> relatedFieldMap,
        Map<String, Object> payload,
        Map<String, Object> data,
        Object rawMatchValue
    ) {
        if (relatedRecord == null ||
            relatedRecord.getSObjectType().getDescribe().getName() != 'Account' ||
            relatedFieldMap == null ||
            relatedFieldMap.isEmpty()) {
            return;
        }

        String derivedName = deriveRequiredNameValue(payload, data, rawMatchValue);
        String derivedFirstName = getFirstString(payload, data, new List<String>{
            'firstName',
            'first_name',
            'accountFirstName',
            'account_first_name'
        });
        String derivedLastName = getFirstString(payload, data, new List<String>{
            'lastName',
            'last_name',
            'accountLastName',
            'account_last_name'
        });
        if (String.isBlank(derivedLastName) && String.isNotBlank(derivedName)) {
            derivedLastName = derivedName;
        }

        String accountLastNameFieldApiName = resolveAccountLastNameFieldApiName(relatedFieldMap);
        if (String.isNotBlank(accountLastNameFieldApiName)) {
            Schema.DescribeFieldResult describe = relatedFieldMap.get(accountLastNameFieldApiName).getDescribe();
            if (isStructurallyWritableField(describe) &&
                isMissingValue(safeGetFieldValue(relatedRecord, accountLastNameFieldApiName)) &&
                String.isNotBlank(derivedLastName)) {
                relatedRecord.put(
                    accountLastNameFieldApiName,
                    normalizeValueForField(derivedLastName, describe)
                );
            }
        }

        String accountFirstNameFieldApiName = resolveAccountFirstNameFieldApiName(relatedFieldMap);
        if (String.isNotBlank(accountFirstNameFieldApiName) && String.isNotBlank(derivedFirstName)) {
            Schema.DescribeFieldResult describe = relatedFieldMap.get(accountFirstNameFieldApiName).getDescribe();
            if (isStructurallyWritableField(describe) &&
                isMissingValue(safeGetFieldValue(relatedRecord, accountFirstNameFieldApiName))) {
                relatedRecord.put(
                    accountFirstNameFieldApiName,
                    normalizeValueForField(derivedFirstName, describe)
                );
            }
        }
    }

    @TestVisible
    private static List<String> getMissingRequiredCreateFields(
        SObject relatedRecord,
        Map<String, Schema.SObjectField> relatedFieldMap
    ) {
        List<String> missingFieldApiNames = new List<String>();
        if (relatedRecord == null || relatedFieldMap == null || relatedFieldMap.isEmpty()) {
            return missingFieldApiNames;
        }

        for (String fieldApiName : relatedFieldMap.keySet()) {
            if (fieldApiName == 'Name' && !isDirectlyAssignableNameField(relatedRecord, relatedFieldMap)) {
                continue;
            }
            Schema.DescribeFieldResult describe = relatedFieldMap.get(fieldApiName).getDescribe();
            if (!isRequiredCreateField(describe)) {
                continue;
            }
            if (isMissingValue(safeGetFieldValue(relatedRecord, fieldApiName))) {
                missingFieldApiNames.add(describe.getName());
            }
        }
        missingFieldApiNames.sort();
        return missingFieldApiNames;
    }

    @TestVisible
    private static Boolean isRequiredCreateField(Schema.DescribeFieldResult describe) {
        return isStructurallyWritableField(describe) &&
            describe != null &&
            !describe.isNillable() &&
            !describe.isDefaultedOnCreate();
    }

    @TestVisible
    private static Boolean isMissingValue(Object value) {
        return value == null || (value instanceof String && String.isBlank((String) value));
    }

    @TestVisible
    private static Object safeGetFieldValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) {
            return null;
        }
        try {
            return record.get(fieldApiName);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String deriveRequiredNameValue(
        Map<String, Object> payload,
        Map<String, Object> data,
        Object rawMatchValue
    ) {
        String explicitName = getFirstString(payload, data, new List<String>{
            'name',
            'full_name',
            'accountName',
            'account_name'
        });
        if (String.isNotBlank(explicitName)) {
            return explicitName;
        }

        String firstName = getFirstString(payload, data, new List<String>{ 'firstName', 'first_name' });
        String lastName = getFirstString(payload, data, new List<String>{ 'lastName', 'last_name' });
        String combinedName = joinNonBlankValues(new List<String>{ firstName, lastName }, ' ');
        if (String.isNotBlank(combinedName)) {
            return combinedName;
        }

        return rawMatchValue == null ? null : String.valueOf(rawMatchValue).trim();
    }

    @TestVisible
    private static String getFirstString(
        Map<String, Object> payload,
        Map<String, Object> data,
        List<String> candidateKeys
    ) {
        if (candidateKeys == null) {
            return null;
        }
        for (String candidateKey : candidateKeys) {
            Object rawValue = getPayloadValue(payload, data, candidateKey);
            if (rawValue == null) {
                continue;
            }

            Object normalizedValue = rawValue;
            if (normalizedValue instanceof List<Object>) {
                List<Object> values = (List<Object>) normalizedValue;
                normalizedValue = values.isEmpty() ? null : values[0];
            }
            if (normalizedValue == null) {
                continue;
            }

            String stringValue = String.valueOf(normalizedValue).trim();
            if (String.isNotBlank(stringValue)) {
                return stringValue;
            }
        }
        return null;
    }

    @TestVisible
    private static String joinNonBlankValues(List<String> values, String delimiter) {
        List<String> parts = new List<String>();
        if (values != null) {
            for (String value : values) {
                if (String.isNotBlank(value)) {
                    parts.add(value.trim());
                }
            }
        }
        return parts.isEmpty() ? null : String.join(parts, delimiter);
    }

    @TestVisible
    private static Boolean isDirectlyAssignableNameField(
        SObject relatedRecord,
        Map<String, Schema.SObjectField> relatedFieldMap
    ) {
        if (relatedRecord == null || relatedFieldMap == null || !relatedFieldMap.containsKey('Name')) {
            return false;
        }

        return relatedRecord.getSObjectType().getDescribe().getName() == 'Account';
    }

    @TestVisible
    private static String resolveAccountLastNameFieldApiName(
        Map<String, Schema.SObjectField> relatedFieldMap
    ) {
        if (relatedFieldMap == null || relatedFieldMap.isEmpty()) {
            return null;
        }

        for (String preferredFieldApiName : new List<String>{ 'LastName', 'litify_pm__Last_Name__c' }) {
            String resolvedFieldApiName = resolveFieldApiName(preferredFieldApiName, relatedFieldMap);
            if (String.isNotBlank(resolvedFieldApiName) &&
                isStructurallyWritableField(relatedFieldMap.get(resolvedFieldApiName).getDescribe())) {
                return resolvedFieldApiName;
            }
        }

        for (String fieldApiName : relatedFieldMap.keySet()) {
            Schema.DescribeFieldResult describe = relatedFieldMap.get(fieldApiName).getDescribe();
            if (isStructurallyWritableField(describe) &&
                describe.getType() == Schema.DisplayType.String &&
                describe.getName().toLowerCase().contains('last')) {
                return describe.getName();
            }
        }
        return null;
    }

    @TestVisible
    private static String resolveAccountFirstNameFieldApiName(
        Map<String, Schema.SObjectField> relatedFieldMap
    ) {
        if (relatedFieldMap == null || relatedFieldMap.isEmpty()) {
            return null;
        }

        for (String preferredFieldApiName : new List<String>{ 'FirstName', 'litify_pm__First_Name__c' }) {
            String resolvedFieldApiName = resolveFieldApiName(preferredFieldApiName, relatedFieldMap);
            if (String.isNotBlank(resolvedFieldApiName) &&
                isStructurallyWritableField(relatedFieldMap.get(resolvedFieldApiName).getDescribe())) {
                return resolvedFieldApiName;
            }
        }

        for (String fieldApiName : relatedFieldMap.keySet()) {
            Schema.DescribeFieldResult describe = relatedFieldMap.get(fieldApiName).getDescribe();
            if (isStructurallyWritableField(describe) &&
                describe.getType() == Schema.DisplayType.String &&
                describe.getName().toLowerCase().contains('first')) {
                return describe.getName();
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
    private static Boolean isStructurallyQueryableField(Schema.DescribeFieldResult describe) {
        if (describe == null || !describe.isFilterable()) {
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
}
