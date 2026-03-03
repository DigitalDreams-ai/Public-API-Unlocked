/**
 * Handles outbound webhook delivery for status changes on Unbounce-created Intakes.
 */
public without sharing class UnbounceIntakeStatusUpdateTriggerHandler {
    private static Set<String> processedEventKeys = new Set<String>();
    private static Set<Id> processedIntakeIds = new Set<Id>();

    public static void handleAfterUpdate(
        List<litify_pm__Intake__c> newIntakes,
        Map<Id, litify_pm__Intake__c> oldMap
    ) {
        if (newIntakes == null || newIntakes.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        List<UnbounceIntakeStatusUpdateQueueable.DeliveryItem> items =
            new List<UnbounceIntakeStatusUpdateQueueable.DeliveryItem>();

        for (litify_pm__Intake__c newIntake : newIntakes) {
            litify_pm__Intake__c oldIntake = oldMap.get(newIntake.Id);
            if (!isUnbounceIntake(newIntake) || oldIntake == null || !didStatusChange(newIntake, oldIntake)) {
                continue;
            }
            if (processedIntakeIds.contains(newIntake.Id)) {
                continue;
            }

            String eventKey =
                String.valueOf(newIntake.Id) + ':' +
                normalizeStatus((String) oldIntake.get('litify_pm__Status__c')) + ':' +
                normalizeStatus((String) newIntake.get('litify_pm__Status__c'));
            if (processedEventKeys.contains(eventKey)) {
                continue;
            }
            processedEventKeys.add(eventKey);
            processedIntakeIds.add(newIntake.Id);

            items.add(new UnbounceIntakeStatusUpdateQueueable.DeliveryItem(
                newIntake.Id,
                normalizeStatus((String) oldIntake.get('litify_pm__Status__c')),
                normalizeStatus((String) newIntake.get('litify_pm__Status__c')),
                System.now()
            ));
        }

        if (!items.isEmpty()) {
            UnbounceIntakeStatusUpdateQueueable.enqueue(items);
        }
    }

    @TestVisible
    private static Boolean isUnbounceIntake(litify_pm__Intake__c intake) {
        return intake != null && ((Boolean) intake.get('Created_By_Unbounce_API__c')) == true;
    }

    @TestVisible
    private static Boolean didStatusChange(
        litify_pm__Intake__c newIntake,
        litify_pm__Intake__c oldIntake
    ) {
        return normalizeStatus((String) newIntake.get('litify_pm__Status__c')) !=
            normalizeStatus((String) oldIntake.get('litify_pm__Status__c'));
    }

    private static String normalizeStatus(String status) {
        return status == null ? null : status.trim();
    }
}
