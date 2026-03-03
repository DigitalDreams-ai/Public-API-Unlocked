/**
 * Sends outbound webhook notifications when a Unbounce-created Intake changes status.
 */
public without sharing class UnbounceIntakeStatusUpdateQueueable implements Queueable, Database.AllowsCallouts {

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

        List<DeliveryItem> items = deserializeItems(serializedItems);
        if (items.isEmpty()) {
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
            'status' => intake.litify_pm__Status__c,
            'previousStatus' => item.previousStatus,
            'changedAt' => formatAsIso8601(item.changedAt),
            'firstName' => intake.litify_pm__First_Name__c,
            'lastName' => intake.litify_pm__Last_Name__c,
            'email' => intake.litify_pm__Email__c,
            'phone' => intake.litify_pm__Phone__c
        };
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
                   litify_pm__Phone__c,
                   litify_pm__Status__c
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
