public without sharing class PublicApiRelatedRecordQueueable implements Queueable {
    @TestVisible static final Integer MAX_REQUESTS_PER_JOB = 90;

    public class RequestItem {
        public Id configId;
        public Id auditRecordId;
        public Id targetRecordId;
        public String targetObjectApiName;
        public String payloadJson;
        public String relatedRecordConfigurationJson;

        public RequestItem() {}

        public RequestItem(
            Id configId,
            Id auditRecordId,
            Id targetRecordId,
            String targetObjectApiName,
            String payloadJson,
            String relatedRecordConfigurationJson
        ) {
            this.configId = configId;
            this.auditRecordId = auditRecordId;
            this.targetRecordId = targetRecordId;
            this.targetObjectApiName = targetObjectApiName;
            this.payloadJson = payloadJson;
            this.relatedRecordConfigurationJson = relatedRecordConfigurationJson;
        }
    }

    private List<String> serializedItems;

    public PublicApiRelatedRecordQueueable(List<String> serializedItems) {
        this.serializedItems = serializedItems == null ? new List<String>() : serializedItems;
    }

    public static void enqueue(List<RequestItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        List<String> serialized = new List<String>();
        for (RequestItem item : items) {
            serialized.add(JSON.serialize(item));
        }
        System.enqueueJob(new PublicApiRelatedRecordQueueable(serialized));
    }

    public void execute(QueueableContext context) {
        if (serializedItems == null || serializedItems.isEmpty()) {
            return;
        }

        List<String> currentBatchSerialized = takeBatch(serializedItems);
        List<String> remainingSerialized = dropBatch(serializedItems);
        List<RequestItem> items = deserializeItems(currentBatchSerialized);
        if (!items.isEmpty()) {
            PublicApiRelatedRecordEventService.processRequests(items);
        }
        if (!remainingSerialized.isEmpty()) {
            System.enqueueJob(new PublicApiRelatedRecordQueueable(remainingSerialized));
        }
    }

    @TestVisible
    static List<RequestItem> deserializeItems(List<String> serializedItems) {
        List<RequestItem> items = new List<RequestItem>();
        if (serializedItems == null) {
            return items;
        }

        for (String serialized : serializedItems) {
            if (String.isBlank(serialized)) {
                continue;
            }
            try {
                items.add((RequestItem) JSON.deserialize(serialized, RequestItem.class));
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

        Integer limitSize = Math.min(MAX_REQUESTS_PER_JOB, sourceItems.size());
        for (Integer index = 0; index < limitSize; index++) {
            batch.add(sourceItems[index]);
        }
        return batch;
    }

    @TestVisible
    static List<String> dropBatch(List<String> sourceItems) {
        List<String> remaining = new List<String>();
        if (sourceItems == null || sourceItems.size() <= MAX_REQUESTS_PER_JOB) {
            return remaining;
        }

        for (Integer index = MAX_REQUESTS_PER_JOB; index < sourceItems.size(); index++) {
            remaining.add(sourceItems[index]);
        }
        return remaining;
    }
}
