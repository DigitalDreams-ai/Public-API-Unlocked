public without sharing class PublicApiConfigRepository {
    public static List<PublicApi_Integration_Config__c> findActiveByApiKey(String apiKey, Integer limitSize) {
        if (String.isBlank(apiKey)) {
            return new List<PublicApi_Integration_Config__c>();
        }
        Integer resolvedLimit = (limitSize == null || limitSize <= 0) ? 1 : limitSize;
        String trimmedApiKey = apiKey.trim();
        return [
            SELECT Id,
                   Is_Active__c,
                   Webhook_Secret__c,
                   API_Key__c,
                   Endpoint_Path__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Target_Record_Type_Developer_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Is_Active__c = true
            AND API_Key__c = :trimmedApiKey
            ORDER BY CreatedDate DESC
            LIMIT :resolvedLimit
        ];
    }

    public static List<PublicApi_Integration_Config__c> findActiveByEndpointPath(String endpointPath, Integer limitSize) {
        if (String.isBlank(endpointPath)) {
            return new List<PublicApi_Integration_Config__c>();
        }
        Integer resolvedLimit = (limitSize == null || limitSize <= 0) ? 1 : limitSize;
        String normalizedEndpointPath = PublicApiEndpointPathService.normalizeConfiguredPath(endpointPath);
        if (normalizedEndpointPath == PublicApiEndpointPathService.DEFAULT_ENDPOINT_PATH) {
            return [
                SELECT Id,
                       Is_Active__c,
                       Webhook_Secret__c,
                       API_Key__c,
                       Endpoint_Path__c,
                       Outbound_Trigger_Enabled__c,
                       Outbound_Trigger_Field_Name__c,
                       Outbound_Trigger_Field_Values__c,
                       Outbound_Webhook_URL__c,
                       Outbound_Remote_Site_Domain__c,
                       Outbound_Remote_Site_Name__c,
                       Outbound_Remote_Site_Status__c,
                       Outbound_Remote_Site_Last_Error__c,
                       Outbound_Remote_Site_Last_Provisioned_At__c,
                       Outbound_Webhook_Secret__c,
                       Outbound_Auth_Mode__c,
                       Outbound_Header_Name__c,
                       Outbound_Header_Value__c,
                       Outbound_Additional_Headers_JSON__c,
                       Outbound_Content_Type__c,
                       Inbound_Payload_Configuration__c,
                       Outbound_Payload_Configuration__c,
                       Related_Record_Configuration__c,
                       Target_Object_API_Name__c,
                       Target_Record_Type_Developer_Name__c,
                       Sync_Inbound_And_Outbound__c
                FROM PublicApi_Integration_Config__c
                WHERE Is_Active__c = true
                AND (Endpoint_Path__c = :normalizedEndpointPath OR Endpoint_Path__c = null)
                ORDER BY CreatedDate DESC
                LIMIT :resolvedLimit
            ];
        }
        return [
            SELECT Id,
                   Is_Active__c,
                   Webhook_Secret__c,
                   API_Key__c,
                   Endpoint_Path__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Target_Record_Type_Developer_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Is_Active__c = true
            AND Endpoint_Path__c = :normalizedEndpointPath
            ORDER BY CreatedDate DESC
            LIMIT :resolvedLimit
        ];
    }

    public static PublicApi_Integration_Config__c findById(Id configId) {
        if (configId == null) {
            return null;
        }

        List<PublicApi_Integration_Config__c> records = [
            SELECT Id,
                   Is_Active__c,
                   Webhook_Secret__c,
                   API_Key__c,
                   Endpoint_Path__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Target_Record_Type_Developer_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Id = :configId
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static PublicApi_Integration_Config__c findActiveById(Id configId) {
        PublicApi_Integration_Config__c record = findById(configId);
        return record != null && record.Is_Active__c ? record : null;
    }

    public static List<PublicApi_Integration_Config__c> findActiveByIds(Set<Id> configIds) {
        if (configIds == null || configIds.isEmpty()) {
            return new List<PublicApi_Integration_Config__c>();
        }

        return [
            SELECT Id,
                   Is_Active__c,
                   Webhook_Secret__c,
                   API_Key__c,
                   Endpoint_Path__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Target_Record_Type_Developer_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Id IN :configIds
            AND Is_Active__c = true
        ];
    }

    public static List<PublicApi_Integration_Config__c> findActiveByTargetObjectApiName(String targetObjectApiName) {
        String normalizedTargetObjectApiName = String.isBlank(targetObjectApiName)
            ? null
            : targetObjectApiName.trim();
        if (String.isBlank(normalizedTargetObjectApiName)) {
            return new List<PublicApi_Integration_Config__c>();
        }

        return [
            SELECT Id,
                   Is_Active__c,
                   Webhook_Secret__c,
                   API_Key__c,
                   Endpoint_Path__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Target_Record_Type_Developer_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Is_Active__c = true
            AND Target_Object_API_Name__c = :normalizedTargetObjectApiName
            ORDER BY CreatedDate DESC
        ];
    }

    public static List<PublicApi_Integration_Config__c> findByEndpointPath(String endpointPath, Integer limitSize) {
        if (String.isBlank(endpointPath)) {
            return new List<PublicApi_Integration_Config__c>();
        }
        Integer resolvedLimit = (limitSize == null || limitSize <= 0) ? 1 : limitSize;
        String normalizedEndpointPath = PublicApiEndpointPathService.normalizeConfiguredPath(endpointPath);
        if (normalizedEndpointPath == PublicApiEndpointPathService.DEFAULT_ENDPOINT_PATH) {
            return [
                SELECT Id,
                       Is_Active__c,
                       Webhook_Secret__c,
                       API_Key__c,
                       Endpoint_Path__c,
                       Outbound_Trigger_Enabled__c,
                       Outbound_Trigger_Field_Name__c,
                       Outbound_Trigger_Field_Values__c,
                       Outbound_Webhook_URL__c,
                       Outbound_Remote_Site_Domain__c,
                       Outbound_Remote_Site_Name__c,
                       Outbound_Remote_Site_Status__c,
                       Outbound_Remote_Site_Last_Error__c,
                       Outbound_Remote_Site_Last_Provisioned_At__c,
                       Outbound_Webhook_Secret__c,
                       Outbound_Auth_Mode__c,
                       Outbound_Header_Name__c,
                       Outbound_Header_Value__c,
                       Outbound_Additional_Headers_JSON__c,
                       Outbound_Content_Type__c,
                       Inbound_Payload_Configuration__c,
                       Outbound_Payload_Configuration__c,
                       Related_Record_Configuration__c,
                       Target_Object_API_Name__c,
                       Target_Record_Type_Developer_Name__c,
                       Sync_Inbound_And_Outbound__c
                FROM PublicApi_Integration_Config__c
                WHERE Endpoint_Path__c = :normalizedEndpointPath
                   OR Endpoint_Path__c = null
                ORDER BY CreatedDate DESC
                LIMIT :resolvedLimit
            ];
        }

        return [
            SELECT Id,
                   Is_Active__c,
                   Webhook_Secret__c,
                   API_Key__c,
                   Endpoint_Path__c,
                   Outbound_Trigger_Enabled__c,
                   Outbound_Trigger_Field_Name__c,
                   Outbound_Trigger_Field_Values__c,
                   Outbound_Webhook_URL__c,
                   Outbound_Remote_Site_Domain__c,
                   Outbound_Remote_Site_Name__c,
                   Outbound_Remote_Site_Status__c,
                   Outbound_Remote_Site_Last_Error__c,
                   Outbound_Remote_Site_Last_Provisioned_At__c,
                   Outbound_Webhook_Secret__c,
                   Outbound_Auth_Mode__c,
                   Outbound_Header_Name__c,
                   Outbound_Header_Value__c,
                   Outbound_Additional_Headers_JSON__c,
                   Outbound_Content_Type__c,
                   Inbound_Payload_Configuration__c,
                   Outbound_Payload_Configuration__c,
                   Related_Record_Configuration__c,
                   Target_Object_API_Name__c,
                   Target_Record_Type_Developer_Name__c,
                   Sync_Inbound_And_Outbound__c
            FROM PublicApi_Integration_Config__c
            WHERE Endpoint_Path__c = :normalizedEndpointPath
            ORDER BY CreatedDate DESC
            LIMIT :resolvedLimit
        ];
    }
}
