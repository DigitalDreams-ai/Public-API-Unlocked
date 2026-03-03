/**
 * Sends outbound webhook notifications when a Unbounce-created Intake changes status.
 */
public without sharing class UnbounceIntakeStatusUpdateQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final Integer MAX_DELIVERIES_PER_JOB = 90;

    public class DeliveryItem {
        public Id intakeId;
        public Id configId;
        public String previousStatus;
        public String currentStatus;
        public Datetime changedAt;

        public DeliveryItem(Id intakeId, Id configId, String previousStatus, String currentStatus, Datetime changedAt) {
            this.intakeId = intakeId;
            this.configId = configId;
            this.previousStatus = previousStatus;
            this.currentStatus = currentStatus;
            this.changedAt = changedAt;
        }
    }

    private List<String> serializedItems;

    public UnbounceIntakeStatusUpdateQueueable(List<String> serializedItems) {
        this.serializedItems = serializedItems != null ? serializedItems : new List<String>();
    }

    public static void enqueue(List<DeliveryItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        List<String> serialized = new List<String>();
        for (DeliveryItem item : items) {
            serialized.add(JSON.serialize(item));
        }
        System.enqueueJob(new UnbounceIntakeStatusUpdateQueueable(serialized));
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

        Map<Id, litify_pm__Intake__c> intakesById = queryIntakes(items);
        Map<Id, UnbounceConfigService.Config> configsById = resolveConfigsById(items);
        Http http = new Http();

        for (DeliveryItem item : items) {
            litify_pm__Intake__c intake = intakesById.get(item.intakeId);
            if (intake == null || item == null || item.configId == null) {
                continue;
            }
            UnbounceConfigService.Config config = configsById.get(item.configId);
            if (config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
                continue;
            }

            String payload = JSON.serialize(buildPayload(intake, item));
            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setEndpoint(config.statusUpdateWebhookUrl);
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('X-Unbounce-Event-Type', 'status_changed');
            request.setBody(payload);

            if (String.isNotBlank(config.statusUpdateWebhookSecret)) {
                String signature = UnbounceClient.generateWebhookSignature(payload, config.statusUpdateWebhookSecret);
                if (String.isNotBlank(signature)) {
                    request.setHeader('x-unbounce-signature', signature);
                }
            }

            try {
                HttpResponse response = http.send(request);
                if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Unbounce intake status webhook failed for Intake ' + intake.Id +
                        ' with status code ' + response.getStatusCode() +
                        ' and body ' + response.getBody()
                    );
                }
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.WARN,
                    'Unbounce intake status webhook callout failed for Intake ' + intake.Id + ': ' + e.getMessage()
                );
            }
        }

        enqueueSerializedItems(remainingSerialized);
    }

    @TestVisible
    private static List<DeliveryItem> deserializeItems(List<String> serializedItems) {
        List<DeliveryItem> items = new List<DeliveryItem>();
        for (String serialized : serializedItems) {
            if (String.isBlank(serialized)) {
                continue;
            }
            items.add((DeliveryItem) JSON.deserialize(serialized, DeliveryItem.class));
        }
        return items;
    }

    @TestVisible
    private static Map<String, Object> buildPayload(litify_pm__Intake__c intake, DeliveryItem item) {
        return new Map<String, Object>{
            'eventType' => 'status_changed',
            'source' => 'Unbounce',
            'intakeId' => String.valueOf(intake.Id),
            'intakeName' => intake.Name,
            'status' => item.currentStatus,
            'previousStatus' => item.previousStatus,
            'changedAt' => formatAsIso8601(item.changedAt),
            'firstName' => intake.litify_pm__First_Name__c,
            'lastName' => intake.litify_pm__Last_Name__c,
            'email' => intake.litify_pm__Email__c,
            'phone' => intake.litify_pm__Phone__c
        };
    }

    @TestVisible
    private static List<String> takeBatch(List<String> sourceItems) {
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
    private static List<String> dropBatch(List<String> sourceItems) {
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
        System.enqueueJob(new UnbounceIntakeStatusUpdateQueueable(remainingSerialized));
    }

    private static Map<Id, litify_pm__Intake__c> queryIntakes(List<DeliveryItem> items) {
        Set<Id> intakeIds = new Set<Id>();
        for (DeliveryItem item : items) {
            if (item != null && item.intakeId != null) {
                intakeIds.add(item.intakeId);
            }
        }
        if (intakeIds.isEmpty()) {
            return new Map<Id, litify_pm__Intake__c>();
        }

        return new Map<Id, litify_pm__Intake__c>([
            SELECT Id,
                   Name,
                   litify_pm__First_Name__c,
                   litify_pm__Last_Name__c,
                   litify_pm__Email__c,
                   litify_pm__Phone__c
            FROM litify_pm__Intake__c
            WHERE Id IN :intakeIds
        ]);
    }

    private static Map<Id, UnbounceConfigService.Config> resolveConfigsById(List<DeliveryItem> items) {
        Set<Id> configIds = new Set<Id>();
        for (DeliveryItem item : items) {
            Id configId = item != null ? item.configId : null;
            if (configId != null) {
                configIds.add(configId);
            }
        }
        return UnbounceConfigService.getConfigsById(configIds);
    }

    private static String formatAsIso8601(Datetime value) {
        return value == null ? null : value.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }
}
