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

    public static void applyDefaultTargetRecordType(SObject record) {
        if (record == null) {
            return;
        }

        String objectApiName = record.getSObjectType().getDescribe().getName();
        String preferredDeveloperName = getPreferredRecordTypeDeveloperName(
            objectApiName,
            DEFAULT_TARGET_RECORD_TYPE_BY_OBJECT
        );
        if (String.isBlank(preferredDeveloperName)) {
            return;
        }

        applyRecordTypeByDeveloperName(record, preferredDeveloperName);
    }

    public static void applyDefaultRelatedRecordType(SObject record) {
        if (record == null) {
            return;
        }

        String objectApiName = record.getSObjectType().getDescribe().getName();
        String preferredDeveloperName = getPreferredRecordTypeDeveloperName(
            objectApiName,
            DEFAULT_RELATED_RECORD_TYPE_BY_OBJECT
        );
        if (String.isBlank(preferredDeveloperName)) {
            return;
        }

        applyRecordTypeByDeveloperName(record, preferredDeveloperName);
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
    static String getPreferredRecordTypeDeveloperName(String objectApiName) {
        return getPreferredRecordTypeDeveloperName(objectApiName, DEFAULT_TARGET_RECORD_TYPE_BY_OBJECT);
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
    static Id getRecordTypeId(Schema.SObjectType objectType, String developerName) {
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
