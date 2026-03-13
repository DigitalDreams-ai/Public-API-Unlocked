public without sharing class PublicApiRecordTypeService {
    public static void applyTargetRecordType(SObject record, String configuredDeveloperName) {
        if (record == null) {
            return;
        }

        if (String.isBlank(configuredDeveloperName)) {
            return;
        }

        applyRecordTypeByDeveloperName(record, configuredDeveloperName.trim());
    }

    public static void applyRelatedRecordType(SObject record, String configuredDeveloperName) {
        if (record == null) {
            return;
        }

        if (String.isBlank(configuredDeveloperName)) {
            return;
        }

        applyRecordTypeByDeveloperName(record, configuredDeveloperName.trim());
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
