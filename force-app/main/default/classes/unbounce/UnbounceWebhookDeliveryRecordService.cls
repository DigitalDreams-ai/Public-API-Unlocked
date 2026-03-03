public without sharing class UnbounceWebhookDeliveryRecordService {
    public class DeliveryResult {
        public Boolean success;
        public Integer statusCode;
        public String responseBody;
        public String message;
        public String exceptionMessage;
    }

    public static Unbounce_Webhook_Delivery__c createDeliveryRecord(
        Id configId,
        Id intakeId,
        String triggeredStatus,
        String webhookUrl,
        String requestJson,
        DeliveryResult result
    ) {
        if (configId == null || result == null) {
            return null;
        }

        Datetime attemptedAt = Datetime.now();
        String responseJson = buildResponseJson(result, attemptedAt);
        Unbounce_Webhook_Delivery__c delivery = new Unbounce_Webhook_Delivery__c(
            Unbounce_Integration_Config__c = configId,
            Intake__c = intakeId,
            Triggered_Status__c = triggeredStatus,
            Status__c = result.success ? 'Success' : 'Failed',
            Status_Code__c = result.statusCode,
            Delivery_Attempt__c = attemptedAt,
            Webhook_URL__c = webhookUrl,
            Request_JSON__c = truncateForLongText(requestJson),
            Response_JSON__c = responseJson
        );

        try {
            insert delivery;
            updateLatestDeliverySummary(configId, attemptedAt, delivery.Status__c, delivery.Request_JSON__c, responseJson);
            return delivery;
        } catch (DmlException e) {
            System.debug('Failed to create Unbounce webhook delivery record: ' + e.getMessage());
            return null;
        }
    }

    @TestVisible
    private static void updateLatestDeliverySummary(
        Id configId,
        Datetime attemptedAt,
        String status,
        String requestJson,
        String responseJson
    ) {
        if (configId == null) {
            return;
        }

        try {
            update new Unbounce_Integration_Config__c(
                Id = configId,
                Last_Webhook_Delivery_Attempt__c = attemptedAt,
                Last_Webhook_Delivery_Status__c = status,
                Last_Webhook_Request_JSON__c = truncateForLongText(requestJson),
                Last_Webhook_Response_JSON__c = truncateForLongText(responseJson)
            );
        } catch (DmlException e) {
            System.debug('Failed to update Unbounce Integration Config delivery summary: ' + e.getMessage());
        }
    }

    @TestVisible
    private static String buildResponseJson(DeliveryResult result, Datetime attemptedAt) {
        Map<String, Object> responseData = new Map<String, Object>{
            'statusCode' => result.statusCode,
            'responseBody' => result.responseBody,
            'message' => result.message,
            'exceptionMessage' => result.exceptionMessage,
            'timestamp' => attemptedAt == null ? null : attemptedAt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
        };
        return truncateForLongText(JSON.serialize(responseData));
    }

    @TestVisible
    private static String truncateForLongText(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() > 131072 ? value.substring(0, 131072) : value;
    }
}
