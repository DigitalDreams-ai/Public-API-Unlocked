public without sharing class PublicApiRecordTypeService {
    @TestVisible
    static final Map<String, String> DEFAULT_RECORD_TYPE_BY_OBJECT = new Map<String, String>{
        'Account' => 'Individual',
        'litify_pm__Intake__c' => 'Lead_Intake'
    };

    public static void applyDefaultRecordType(SObject record) {
        if (record == null) {
            return;
        }

        String objectApiName = record.getSObjectType().getDescribe().getName();
        String preferredDeveloperName = getPreferredRecordTypeDeveloperName(objectApiName);
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
        if (String.isBlank(objectApiName)) {
            return null;
        }

        if (DEFAULT_RECORD_TYPE_BY_OBJECT.containsKey(objectApiName)) {
            return DEFAULT_RECORD_TYPE_BY_OBJECT.get(objectApiName);
        }

        String normalizedObjectApiName = objectApiName.trim().toLowerCase();
        for (String candidateObjectApiName : DEFAULT_RECORD_TYPE_BY_OBJECT.keySet()) {
            if (candidateObjectApiName != null &&
                candidateObjectApiName.toLowerCase() == normalizedObjectApiName) {
                return DEFAULT_RECORD_TYPE_BY_OBJECT.get(candidateObjectApiName);
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
