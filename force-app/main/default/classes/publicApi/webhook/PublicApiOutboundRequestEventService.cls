public without sharing class PublicApiOutboundRequestEventService {
    @TestVisible static Boolean simulatePublishFailure = false;

    public static void publishRequests(List<PublicApiOutboundTriggerService.ChangeRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<PublicApi_Outbound_Request__e> eventsToPublish = new List<PublicApi_Outbound_Request__e>();
        for (PublicApiOutboundTriggerService.ChangeRequest request : requests) {
            if (request == null || request.recordId == null) {
                continue;
            }
            eventsToPublish.add(new PublicApi_Outbound_Request__e(
                Submission_Record_Id__c = String.valueOf(request.recordId),
                Config_Id__c = request.configId == null ? null : String.valueOf(request.configId),
                Previous_Value__c = request.previousValue,
                Current_Value__c = request.currentValue,
                Changed_At__c = request.changedAt == null ? System.now() : request.changedAt
            ));
        }

        if (!eventsToPublish.isEmpty()) {
            if (Test.isRunningTest() && simulatePublishFailure) {
                throw new PublicApiSubmissionServiceException('Failed to publish outbound delivery event: Simulated publish failure.');
            }

            List<Database.SaveResult> publishResults = EventBus.publish(eventsToPublish);
            for (Database.SaveResult publishResult : publishResults) {
                if (publishResult == null || !publishResult.isSuccess()) {
                    throw new PublicApiSubmissionServiceException(buildPublishFailureMessage(publishResult));
                }
            }
        }
    }

    public static void handleEvents(List<PublicApi_Outbound_Request__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<PublicApiOutboundRequestQueueable.RequestItem> requestItems = toRequestItems(events);
        if (!requestItems.isEmpty()) {
            PublicApiOutboundRequestQueueable.enqueue(requestItems);
        }
    }

    public static void processRequests(List<PublicApiOutboundRequestQueueable.RequestItem> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, PublicApi_Submission__c> submissionsById = getSubmissionRecords(requests);
        if (submissionsById.isEmpty()) {
            return;
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(
            getRequestConfigIds(requests, submissionsById)
        );
        Map<Id, SObject> payloadRecordsById = queryPayloadRecords(submissionsById, requests, configsById);
        Http http = new Http();

        List<PublicApi_Webhook_Delivery__c> deliveryRecords = new List<PublicApi_Webhook_Delivery__c>();
        Map<Id, PublicApi_Integration_Config__c> summaryUpdatesByConfig = new Map<Id, PublicApi_Integration_Config__c>();
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            Id submissionId = requestItem == null ? null : requestItem.submissionId;
            if (submissionId == null) {
                continue;
            }

            PublicApi_Submission__c submissionRecord = submissionsById.get(submissionId);
            Id configId = getRequestConfigId(requestItem, submissionsById);
            if (submissionRecord == null || configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(configId);
            if (config == null || String.isBlank(config.statusUpdateWebhookUrl)) {
                continue;
            }

            String currentValue = PublicApiOutboundTriggerService.normalizeTriggerValue(
                requestItem == null ? null : requestItem.currentValue
            );
            if (!PublicApiOutboundTriggerService.shouldSendOutboundTrigger(config, currentValue)) {
                continue;
            }

            Id payloadRecordId = resolvePayloadRecordId(submissionRecord, config);
            SObject payloadRecord = payloadRecordId == null ? null : payloadRecordsById.get(payloadRecordId);
            PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
                payloadRecord == null
                    ? buildMissingTargetOutcome(submissionRecord)
                    : PublicApiStatusUpdateDeliveryService.sendStatusUpdate(http, payloadRecord, config);

            PublicApi_Webhook_Delivery__c deliveryRecord = PublicApiWebhookDeliveryRecordService.buildDeliveryRecord(
                configId,
                submissionRecord.Id,
                PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME,
                currentValue,
                config.statusUpdateWebhookUrl,
                outcome == null ? null : outcome.payloadJson,
                outcome == null ? buildFallbackDeliveryResult() : outcome.deliveryResult
            );
            if (deliveryRecord != null) {
                deliveryRecords.add(deliveryRecord);
                PublicApiWebhookDeliveryRecordService.mergeLatestDeliverySummary(summaryUpdatesByConfig, deliveryRecord);
            }
        }

        PublicApiWebhookDeliveryRecordService.persistDeliveryResults(deliveryRecords, summaryUpdatesByConfig);
    }

    @TestVisible
    static List<PublicApiOutboundRequestQueueable.RequestItem> toRequestItems(List<PublicApi_Outbound_Request__e> events) {
        List<PublicApiOutboundRequestQueueable.RequestItem> items =
            new List<PublicApiOutboundRequestQueueable.RequestItem>();
        if (events == null) {
            return items;
        }

        for (PublicApi_Outbound_Request__e requestEvent : events) {
            Id submissionId = parseSubmissionId(requestEvent);
            if (submissionId == null) {
                continue;
            }
            items.add(new PublicApiOutboundRequestQueueable.RequestItem(
                submissionId,
                parseConfigId(requestEvent),
                requestEvent.Previous_Value__c,
                requestEvent.Current_Value__c,
                requestEvent.Changed_At__c
            ));
        }
        return items;
    }

    @TestVisible
    static Map<Id, PublicApi_Submission__c> getSubmissionRecords(List<PublicApiOutboundRequestQueueable.RequestItem> requests) {
        Set<Id> submissionIds = new Set<Id>();
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            if (requestItem != null && requestItem.submissionId != null) {
                Id submissionId = requestItem.submissionId;
                submissionIds.add(submissionId);
            }
        }

        Map<Id, PublicApi_Submission__c> submissionsById = new Map<Id, PublicApi_Submission__c>();
        if (submissionIds.isEmpty()) {
            return submissionsById;
        }

        for (PublicApi_Submission__c submissionRecord : [
            SELECT Id,
                   PublicApi_Integration_Config__c,
                   Target_Object_API_Name__c,
                   Target_Record_Id__c
            FROM PublicApi_Submission__c
            WHERE Id IN :submissionIds
        ]) {
            submissionsById.put(submissionRecord.Id, submissionRecord);
        }
        return submissionsById;
    }

    @TestVisible
    static Id getRequestConfigId(
        PublicApiOutboundRequestQueueable.RequestItem requestItem,
        Map<Id, PublicApi_Submission__c> submissionsById
    ) {
        if (requestItem == null || requestItem.submissionId == null) {
            return null;
        }

        if (requestItem.configId != null) {
            return requestItem.configId;
        }

        PublicApi_Submission__c submissionRecord = submissionsById.get(requestItem.submissionId);
        return submissionRecord == null ? null : submissionRecord.PublicApi_Integration_Config__c;
    }

    @TestVisible
    static Set<Id> getRequestConfigIds(
        List<PublicApiOutboundRequestQueueable.RequestItem> requests,
        Map<Id, PublicApi_Submission__c> submissionsById
    ) {
        Set<Id> configIds = new Set<Id>();
        if (requests == null) {
            return configIds;
        }
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            Id configId = getRequestConfigId(requestItem, submissionsById);
            if (configId != null) {
                configIds.add(configId);
            }
        }
        return configIds;
    }

    @TestVisible
    static Id parseSubmissionId(PublicApi_Outbound_Request__e requestEvent) {
        if (requestEvent == null || String.isBlank(requestEvent.Submission_Record_Id__c)) {
            return null;
        }
        try {
            return (Id) requestEvent.Submission_Record_Id__c.trim();
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    static Id parseConfigId(PublicApi_Outbound_Request__e requestEvent) {
        if (requestEvent == null || String.isBlank(requestEvent.Config_Id__c)) {
            return null;
        }
        try {
            return (Id) requestEvent.Config_Id__c.trim();
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    static String buildPublishFailureMessage(Database.SaveResult publishResult) {
        if (publishResult != null) {
            Database.Error[] errors = publishResult.getErrors();
            if (errors != null && !errors.isEmpty() && String.isNotBlank(errors[0].getMessage())) {
                return 'Failed to publish outbound delivery event: ' + errors[0].getMessage();
            }
        }
        return 'Failed to publish outbound delivery event: Unknown publish failure.';
    }

    @TestVisible
    static Id resolvePayloadRecordId(PublicApi_Submission__c submissionRecord, PublicApiConfigService.Config config) {
        if (submissionRecord == null) {
            return null;
        }

        String payloadObjectApiName = normalizePayloadObjectApiName(submissionRecord, config);
        if (String.isBlank(payloadObjectApiName)) {
            return null;
        }

        if (payloadObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME) {
            return submissionRecord.Id;
        }

        if (String.isBlank(submissionRecord.Target_Record_Id__c)) {
            return null;
        }

        try {
            return (Id) submissionRecord.Target_Record_Id__c;
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    static Map<Id, SObject> queryPayloadRecords(
        Map<Id, PublicApi_Submission__c> submissionsById,
        List<PublicApiOutboundRequestQueueable.RequestItem> requests,
        Map<Id, PublicApiConfigService.Config> configsById
    ) {
        Map<String, Set<Id>> recordIdsByObject = new Map<String, Set<Id>>();
        Map<String, Set<Id>> configIdsByObject = new Map<String, Set<Id>>();
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            Id submissionId = requestItem == null ? null : requestItem.submissionId;
            PublicApi_Submission__c submissionRecord = submissionsById.get(submissionId);
            Id configId = getRequestConfigId(requestItem, submissionsById);
            if (submissionRecord == null || configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(configId);
            String payloadObjectApiName = normalizePayloadObjectApiName(submissionRecord, config);
            Id payloadRecordId = resolvePayloadRecordId(submissionRecord, config);
            if (config == null || payloadRecordId == null || String.isBlank(payloadObjectApiName)) {
                continue;
            }

            String objectApiName = payloadObjectApiName.trim();
            if (!recordIdsByObject.containsKey(objectApiName)) {
                recordIdsByObject.put(objectApiName, new Set<Id>());
            }
            recordIdsByObject.get(objectApiName).add(payloadRecordId);

            if (!configIdsByObject.containsKey(objectApiName)) {
                configIdsByObject.put(objectApiName, new Set<Id>());
            }
            configIdsByObject.get(objectApiName).add(configId);
        }

        Map<Id, SObject> recordsById = new Map<Id, SObject>();
        if (recordIdsByObject.isEmpty()) {
            return recordsById;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String objectApiName : recordIdsByObject.keySet()) {
            if (String.isBlank(objectApiName) || !globalDescribe.containsKey(objectApiName)) {
                continue;
            }

            Set<Id> recordIds = recordIdsByObject.get(objectApiName);
            if (recordIds == null || recordIds.isEmpty()) {
                continue;
            }

            Map<String, Schema.SObjectField> validFields = globalDescribe.get(objectApiName).getDescribe().fields.getMap();
            Set<String> selectedFields = new Set<String>{ 'Id' };
            for (Id configId : configIdsByObject.get(objectApiName)) {
                PublicApiConfigService.Config config = configsById.get(configId);
                Set<String> configuredFields = PublicApiRequestMappingService.getOutboundFieldApiNames(
                    config == null ? null : config.outboundPayloadConfiguration,
                    objectApiName
                );
                for (String fieldName : configuredFields) {
                    if (fieldName == 'CreatedDate' || validFields.containsKey(fieldName)) {
                        selectedFields.add(fieldName);
                    }
                }
            }

            String soql = 'SELECT ' + String.join(new List<String>(selectedFields), ', ') +
                ' FROM ' + objectApiName + ' WHERE Id IN :recordIds';
            for (SObject queriedRecord : Database.query(soql)) {
                recordsById.put((Id) queriedRecord.get('Id'), queriedRecord);
            }
        }
        return recordsById;
    }

    private static String normalizePayloadObjectApiName(
        PublicApi_Submission__c submissionRecord,
        PublicApiConfigService.Config config
    ) {
        String submissionObjectApiName = submissionRecord == null ? null : submissionRecord.Target_Object_API_Name__c;
        if (String.isNotBlank(submissionObjectApiName)) {
            return submissionObjectApiName.trim();
        }
        return config == null ? null : config.targetObjectApiName;
    }

    private static PublicApiStatusUpdateDeliveryService.SendOutcome buildMissingTargetOutcome(
        PublicApi_Submission__c submissionRecord
    ) {
        PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
            new PublicApiStatusUpdateDeliveryService.SendOutcome();
        outcome.deliveryResult = new PublicApiWebhookDeliveryRecordService.DeliveryResult();
        outcome.deliveryResult.success = false;
        outcome.deliveryResult.errorCode = PublicApiStatusUpdateDeliveryService.ERROR_CODE_MAPPING_ERROR;
        outcome.deliveryResult.exceptionMessage =
            'Outbound payload source record could not be resolved for submission ' +
            String.valueOf(submissionRecord == null ? null : submissionRecord.Id) +
            ' and target object ' +
            String.valueOf(submissionRecord == null ? null : submissionRecord.Target_Object_API_Name__c) + '.';
        return outcome;
    }

    private static PublicApiWebhookDeliveryRecordService.DeliveryResult buildFallbackDeliveryResult() {
        PublicApiWebhookDeliveryRecordService.DeliveryResult result =
            new PublicApiWebhookDeliveryRecordService.DeliveryResult();
        result.success = false;
        result.errorCode = PublicApiStatusUpdateDeliveryService.ERROR_CODE_UNKNOWN_ERROR;
        result.exceptionMessage = 'Outbound delivery did not produce a result.';
        return result;
    }
}
