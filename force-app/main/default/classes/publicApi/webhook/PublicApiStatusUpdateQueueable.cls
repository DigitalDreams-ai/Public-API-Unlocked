public without sharing class PublicApiStatusUpdateQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible static final Integer MAX_DELIVERIES_PER_JOB = 90;

    public class DeliveryItem {
        public Id recordId;
        public Id configId;
        public String previousStatus;
        public String currentStatus;
        public Datetime changedAt;

        public DeliveryItem() {}

        public DeliveryItem(Id recordId, Id configId, String previousStatus, String currentStatus, Datetime changedAt) {
            this.recordId = recordId;
            this.configId = configId;
            this.previousStatus = previousStatus;
            this.currentStatus = currentStatus;
            this.changedAt = changedAt;
        }
    }

    private List<String> serializedItems;

    public PublicApiStatusUpdateQueueable(List<String> serializedItems) {
        this.serializedItems = serializedItems == null ? new List<String>() : serializedItems;
    }

    public static void enqueue(List<DeliveryItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        List<String> serialized = new List<String>();
        for (DeliveryItem item : items) {
            serialized.add(JSON.serialize(item));
        }
        System.enqueueJob(new PublicApiStatusUpdateQueueable(serialized));
    }

    public void execute(QueueableContext context) {
        if (serializedItems == null || serializedItems.isEmpty()) {
            return;
        }

        List<String> currentBatchSerialized = takeBatch(serializedItems);
        List<String> remainingSerialized = dropBatch(serializedItems);
        List<DeliveryItem> items = deserializeItems(currentBatchSerialized);
        if (items.isEmpty()) {
            enqueueSerializedItems(remainingSerialized);
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = resolveConfigsById(items);
        Map<Id, SObject> recordsById = queryRecords(items, configsById);
        Http http = new Http();

        List<PublicApi_Webhook_Delivery__c> deliveryRecords = new List<PublicApi_Webhook_Delivery__c>();
        Map<Id, PublicApi_Integration_Config__c> summaryUpdatesByConfig = new Map<Id, PublicApi_Integration_Config__c>();

        for (DeliveryItem item : items) {
            if (item == null || item.recordId == null || item.configId == null) {
                continue;
            }
            SObject record = recordsById.get(item.recordId);
            PublicApiConfigService.Config config = configsById.get(item.configId);
            if (record == null || config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
                continue;
            }

            PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
                PublicApiStatusUpdateDeliveryService.sendStatusUpdate(http, record, config);
            String payload = outcome == null ? null : outcome.payloadJson;
            PublicApiWebhookDeliveryRecordService.DeliveryResult result =
                outcome == null ? null : outcome.deliveryResult;
            if (result == null) {
                result = buildDeliveryResult(
                    false,
                    null,
                    PublicApiStatusUpdateDeliveryService.ERROR_CODE_UNKNOWN_ERROR,
                    null,
                    null,
                    'Status update did not produce a result.'
                );
            }

            PublicApi_Webhook_Delivery__c deliveryRecord = PublicApiWebhookDeliveryRecordService.buildDeliveryRecord(
                item.configId,
                item.recordId,
                record.getSObjectType().getDescribe().getName(),
                item.currentStatus,
                config.statusUpdateWebhookUrl,
                payload,
                result
            );
            if (deliveryRecord != null) {
                deliveryRecords.add(deliveryRecord);
                PublicApiWebhookDeliveryRecordService.mergeLatestDeliverySummary(summaryUpdatesByConfig, deliveryRecord);
            }
        }

        PublicApiWebhookDeliveryRecordService.persistDeliveryResults(deliveryRecords, summaryUpdatesByConfig);
        enqueueSerializedItems(remainingSerialized);
    }

    @TestVisible
    static List<DeliveryItem> deserializeItems(List<String> serializedItems) {
        List<DeliveryItem> items = new List<DeliveryItem>();
        for (String serialized : serializedItems) {
            if (String.isBlank(serialized)) {
                continue;
            }
            try {
                items.add((DeliveryItem) JSON.deserialize(serialized, DeliveryItem.class));
            } catch (Exception e) {
                continue;
            }
        }
        return items;
    }

    @TestVisible
    static List<String> takeBatch(List<String> sourceItems) {
        List<String> batch = new List<String>();
        if (sourceItems == null || sourceItems.isEmpty()) {
            return batch;
        }
        Integer limitSize = Math.min(MAX_DELIVERIES_PER_JOB, sourceItems.size());
        for (Integer index = 0; index < limitSize; index++) {
            batch.add(sourceItems[index]);
        }
        return batch;
    }

    @TestVisible
    static List<String> dropBatch(List<String> sourceItems) {
        List<String> remaining = new List<String>();
        if (sourceItems == null || sourceItems.size() <= MAX_DELIVERIES_PER_JOB) {
            return remaining;
        }
        for (Integer index = MAX_DELIVERIES_PER_JOB; index < sourceItems.size(); index++) {
            remaining.add(sourceItems[index]);
        }
        return remaining;
    }

    private static void enqueueSerializedItems(List<String> remainingSerialized) {
        if (remainingSerialized == null || remainingSerialized.isEmpty()) {
            return;
        }
        System.enqueueJob(new PublicApiStatusUpdateQueueable(remainingSerialized));
    }

    private static Map<Id, SObject> queryRecords(
        List<DeliveryItem> items,
        Map<Id, PublicApiConfigService.Config> configsById
    ) {
        return PublicApiStatusUpdateDeliveryService.queryRecords(items, configsById);
    }

    private static Map<Id, PublicApiConfigService.Config> resolveConfigsById(List<DeliveryItem> items) {
        Set<Id> configIds = new Set<Id>();
        for (DeliveryItem item : items) {
            if (item != null && item.configId != null) {
                configIds.add(item.configId);
            }
        }
        return PublicApiConfigService.getConfigsById(configIds);
    }

    @TestVisible
    static PublicApiWebhookDeliveryRecordService.DeliveryResult buildDeliveryResult(
        Boolean success,
        Integer statusCode,
        String errorCode,
        String responseBody,
        String message,
        String exceptionMessage
    ) {
        PublicApiWebhookDeliveryRecordService.DeliveryResult result =
            new PublicApiWebhookDeliveryRecordService.DeliveryResult();
        result.success = success;
        result.statusCode = statusCode;
        result.errorCode = errorCode;
        result.responseBody = responseBody;
        result.message = message;
        result.exceptionMessage = exceptionMessage;
        return result;
    }
}
