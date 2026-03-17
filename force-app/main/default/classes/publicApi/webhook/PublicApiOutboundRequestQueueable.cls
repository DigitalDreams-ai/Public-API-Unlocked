public without sharing class PublicApiOutboundRequestQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible static final Integer MAX_REQUESTS_PER_JOB = 90;

    public class RequestItem {
        public Id submissionId;
        public String previousValue;
        public String currentValue;
        public Datetime changedAt;

        public RequestItem() {}

        public RequestItem(Id submissionId, String previousValue, String currentValue, Datetime changedAt) {
            this.submissionId = submissionId;
            this.previousValue = previousValue;
            this.currentValue = currentValue;
            this.changedAt = changedAt;
        }
    }

    private List<String> serializedItems;

    public PublicApiOutboundRequestQueueable(List<String> serializedItems) {
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
        System.enqueueJob(new PublicApiOutboundRequestQueueable(serialized));
    }

    public void execute(QueueableContext context) {
        if (serializedItems == null || serializedItems.isEmpty()) {
            return;
        }

        List<String> currentBatchSerialized = takeBatch(serializedItems);
        List<String> remainingSerialized = dropBatch(serializedItems);
        List<RequestItem> items = deserializeItems(currentBatchSerialized);
        if (!items.isEmpty()) {
            PublicApiOutboundRequestEventService.processRequests(items);
        }
        if (!remainingSerialized.isEmpty()) {
            System.enqueueJob(new PublicApiOutboundRequestQueueable(remainingSerialized));
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
