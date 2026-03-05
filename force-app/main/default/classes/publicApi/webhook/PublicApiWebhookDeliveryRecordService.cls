public without sharing class PublicApiWebhookDeliveryRecordService {
    public class DeliveryResult {
        public Boolean success;
        public Integer statusCode;
        public String errorCode;
        public String responseBody;
        public String message;
        public String exceptionMessage;
    }

    public static PublicApi_Webhook_Delivery__c createDeliveryRecord(
        Id configId,
        Id intakeId,
        String triggeredStatus,
        String webhookUrl,
        String requestJson,
        DeliveryResult result
    ) {
        PublicApi_Webhook_Delivery__c delivery = buildDeliveryRecord(
            configId,
            intakeId,
            triggeredStatus,
            webhookUrl,
            requestJson,
            result
        );
        if (delivery == null) {
            return null;
        }

        Map<Id, PublicApi_Integration_Config__c> summaryUpdatesByConfig =
            new Map<Id, PublicApi_Integration_Config__c>();
        mergeLatestDeliverySummary(summaryUpdatesByConfig, delivery);
        persistDeliveryResults(
            new List<PublicApi_Webhook_Delivery__c>{ delivery },
            summaryUpdatesByConfig
        );
        return delivery;
    }

    public static PublicApi_Webhook_Delivery__c buildDeliveryRecord(
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
        return new PublicApi_Webhook_Delivery__c(
            PublicApi_Integration_Config__c = configId,
            Intake__c = intakeId,
            Triggered_Status__c = triggeredStatus,
            Status__c = result.success ? 'Success' : 'Failed',
            Status_Code__c = result.statusCode,
            Error_Code__c = result.errorCode,
            Delivery_Attempt__c = attemptedAt,
            Webhook_URL__c = webhookUrl,
            Request_JSON__c = truncateForLongText(requestJson),
            Response_JSON__c = responseJson
        );
    }

    public static void mergeLatestDeliverySummary(
        Map<Id, PublicApi_Integration_Config__c> summaryUpdatesByConfig,
        PublicApi_Webhook_Delivery__c delivery
    ) {
        if (summaryUpdatesByConfig == null ||
            delivery == null ||
            delivery.PublicApi_Integration_Config__c == null) {
            return;
        }

        Id configId = delivery.PublicApi_Integration_Config__c;
        PublicApi_Integration_Config__c existingSummary = summaryUpdatesByConfig.get(configId);
        if (existingSummary != null &&
            existingSummary.Last_Webhook_Delivery_Attempt__c != null &&
            delivery.Delivery_Attempt__c != null &&
            existingSummary.Last_Webhook_Delivery_Attempt__c.getTime() >
                delivery.Delivery_Attempt__c.getTime()) {
            return;
        }

        summaryUpdatesByConfig.put(
            configId,
            new PublicApi_Integration_Config__c(
                Id = configId,
                Last_Webhook_Delivery_Attempt__c = delivery.Delivery_Attempt__c,
                Last_Webhook_Delivery_Status__c = delivery.Status__c,
                Last_Webhook_Request_JSON__c = truncateForLongText(delivery.Request_JSON__c),
                Last_Webhook_Response_JSON__c = truncateForLongText(delivery.Response_JSON__c)
            )
        );
    }

    public static void persistDeliveryResults(
        List<PublicApi_Webhook_Delivery__c> deliveries,
        Map<Id, PublicApi_Integration_Config__c> summaryUpdatesByConfig
    ) {
        if (deliveries != null && !deliveries.isEmpty()) {
            Database.SaveResult[] deliveryResults = Database.insert(deliveries, false);
            for (Integer index = 0; index < deliveryResults.size(); index++) {
                if (!deliveryResults[index].isSuccess()) {
                    System.debug(
                        'Failed to create PublicApi webhook delivery record: ' +
                        deliveryResults[index].getErrors()[0].getMessage()
                    );
                }
            }
        }

        if (summaryUpdatesByConfig != null && !summaryUpdatesByConfig.isEmpty()) {
            List<PublicApi_Integration_Config__c> summaryUpdates = summaryUpdatesByConfig.values();
            Database.SaveResult[] summaryResults = Database.update(summaryUpdates, false);
            for (Integer index = 0; index < summaryResults.size(); index++) {
                if (!summaryResults[index].isSuccess()) {
                    System.debug(
                        'Failed to update Public API Integration Config delivery summary: ' +
                        summaryResults[index].getErrors()[0].getMessage()
                    );
                }
            }
        }
    }

    @TestVisible
    private static String buildResponseJson(DeliveryResult result, Datetime attemptedAt) {
        Map<String, Object> responseData = new Map<String, Object>{
            'statusCode' => result.statusCode,
            'errorCode' => result.errorCode,
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
