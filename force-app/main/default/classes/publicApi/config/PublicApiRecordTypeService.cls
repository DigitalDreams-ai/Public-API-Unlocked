public without sharing class PublicApiRecordTypeService {
    @TestVisible
    static final Map<String, String> DEFAULT_TARGET_RECORD_TYPE_BY_OBJECT = new Map<String, String>{
        'Account' => 'Individual',
        'litify_pm__Intake__c' => 'Lead_Intake'
    };

    @TestVisible
    static final Map<String, String> DEFAULT_RELATED_RECORD_TYPE_BY_OBJECT = new Map<String, String>{
        'Account' => 'Individual'
    };

    public static void applyTargetRecordType(SObject record, String configuredDeveloperName) {
        if (record == null) {
            return;
        }

        String objectApiName = record.getSObjectType().getDescribe().getName();
        String preferredDeveloperName = getEffectiveRecordTypeDeveloperName(
            objectApiName,
            configuredDeveloperName,
            DEFAULT_TARGET_RECORD_TYPE_BY_OBJECT
        );
        if (String.isBlank(preferredDeveloperName)) {
            return;
        }

        applyRecordTypeByDeveloperName(record, preferredDeveloperName);
    }

    public static void applyRelatedRecordType(SObject record, String configuredDeveloperName) {
        if (record == null) {
            return;
        }

        String objectApiName = record.getSObjectType().getDescribe().getName();
        String preferredDeveloperName = getEffectiveRecordTypeDeveloperName(
            objectApiName,
            configuredDeveloperName,
            DEFAULT_RELATED_RECORD_TYPE_BY_OBJECT
        );
        if (String.isBlank(preferredDeveloperName)) {
            return;
        }

        applyRecordTypeByDeveloperName(record, preferredDeveloperName);
    }

    public static List<String> getAvailableRecordTypeDeveloperNames(String objectApiName) {
        Schema.SObjectType objectType = resolveSObjectType(objectApiName);
        if (objectType == null) {
            return new List<String>();
        }

        List<String> developerNames = new List<String>();
        for (Schema.RecordTypeInfo recordTypeInfo :
            objectType.getDescribe().getRecordTypeInfosByDeveloperName().values()) {
            if (recordTypeInfo != null && recordTypeInfo.isActive()) {
                developerNames.add(recordTypeInfo.getDeveloperName());
            }
        }
        developerNames.sort();
        return developerNames;
    }

    @TestVisible
    static void applyRecordTypeByDeveloperName(SObject record, String developerName) {
        if (record == null || String.isBlank(developerName)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = record.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey('RecordTypeId')) {
            return;
        }
        if (record.get('RecordTypeId') != null) {
            return;
        }

        Id recordTypeId = getRecordTypeId(record.getSObjectType(), developerName);
        if (recordTypeId != null) {
            record.put('RecordTypeId', recordTypeId);
        }
    }

    @TestVisible
    static String getDefaultTargetRecordTypeDeveloperName(String objectApiName) {
        return getPreferredRecordTypeDeveloperName(objectApiName, DEFAULT_TARGET_RECORD_TYPE_BY_OBJECT);
    }

    @TestVisible
    static String getDefaultRelatedRecordTypeDeveloperName(String objectApiName) {
        return getPreferredRecordTypeDeveloperName(objectApiName, DEFAULT_RELATED_RECORD_TYPE_BY_OBJECT);
    }

    @TestVisible
    static String getEffectiveTargetRecordTypeDeveloperName(
        String objectApiName,
        String configuredDeveloperName
    ) {
        return getEffectiveRecordTypeDeveloperName(
            objectApiName,
            configuredDeveloperName,
            DEFAULT_TARGET_RECORD_TYPE_BY_OBJECT
        );
    }

    @TestVisible
    static String getEffectiveRelatedRecordTypeDeveloperName(
        String objectApiName,
        String configuredDeveloperName
    ) {
        return getEffectiveRecordTypeDeveloperName(
            objectApiName,
            configuredDeveloperName,
            DEFAULT_RELATED_RECORD_TYPE_BY_OBJECT
        );
    }

    @TestVisible
    static String getEffectiveRecordTypeDeveloperName(
        String objectApiName,
        String configuredDeveloperName,
        Map<String, String> defaultsByObject
    ) {
        if (String.isNotBlank(configuredDeveloperName)) {
            return configuredDeveloperName.trim();
        }
        return getPreferredRecordTypeDeveloperName(objectApiName, defaultsByObject);
    }

    @TestVisible
    static String getPreferredRecordTypeDeveloperName(
        String objectApiName,
        Map<String, String> defaultsByObject
    ) {
        if (String.isBlank(objectApiName)) {
            return null;
        }

        if (defaultsByObject == null || defaultsByObject.isEmpty()) {
            return null;
        }

        if (defaultsByObject.containsKey(objectApiName)) {
            return defaultsByObject.get(objectApiName);
        }

        String normalizedObjectApiName = objectApiName.trim().toLowerCase();
        for (String candidateObjectApiName : defaultsByObject.keySet()) {
            if (candidateObjectApiName != null &&
                candidateObjectApiName.toLowerCase() == normalizedObjectApiName) {
                return defaultsByObject.get(candidateObjectApiName);
            }
        }
        return null;
    }

    @TestVisible
    static Schema.SObjectType resolveSObjectType(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (globalDescribe.containsKey(objectApiName)) {
            return globalDescribe.get(objectApiName);
        }

        String normalizedObjectApiName = objectApiName.trim().toLowerCase();
        for (String candidateObjectApiName : globalDescribe.keySet()) {
            if (candidateObjectApiName != null &&
                candidateObjectApiName.toLowerCase() == normalizedObjectApiName) {
                return globalDescribe.get(candidateObjectApiName);
            }
        }
        return null;
    }

    @TestVisible
    public static Id getRecordTypeId(Schema.SObjectType objectType, String developerName) {
        if (objectType == null || String.isBlank(developerName)) {
            return null;
        }

        Map<String, Schema.RecordTypeInfo> byDeveloperName =
            objectType.getDescribe().getRecordTypeInfosByDeveloperName();
        if (byDeveloperName == null || byDeveloperName.isEmpty()) {
            return null;
        }
        if (byDeveloperName.containsKey(developerName)) {
            return byDeveloperName.get(developerName).getRecordTypeId();
        }

        String normalizedDeveloperName = developerName.trim().toLowerCase();
        for (String candidateDeveloperName : byDeveloperName.keySet()) {
            if (candidateDeveloperName != null &&
                candidateDeveloperName.toLowerCase() == normalizedDeveloperName) {
                return byDeveloperName.get(candidateDeveloperName).getRecordTypeId();
            }
        }
        return null;
    }
}
