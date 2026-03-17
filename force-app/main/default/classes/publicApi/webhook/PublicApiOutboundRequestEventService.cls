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

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(
            getRequestConfigIds(requests)
        );
        Map<Id, SObject> payloadRecordsById = queryPayloadRecords(requests, configsById);
        Map<String, PublicApi_Submission__c> submissionsBySourceKey = getSubmissionRecords(requests, configsById);
        Http http = new Http();

        List<PublicApi_Webhook_Delivery__c> deliveryRecords = new List<PublicApi_Webhook_Delivery__c>();
        Map<Id, PublicApi_Integration_Config__c> summaryUpdatesByConfig = new Map<Id, PublicApi_Integration_Config__c>();
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            Id sourceRecordId = requestItem == null ? null : requestItem.sourceRecordId;
            Id configId = requestItem == null ? null : requestItem.configId;
            if (sourceRecordId == null || configId == null) {
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

            PublicApi_Submission__c submissionRecord = resolveSubmissionRecord(
                requestItem,
                config,
                submissionsBySourceKey
            );
            SObject payloadRecord = payloadRecordsById.get(sourceRecordId);
            PublicApiStatusUpdateDeliveryService.SendOutcome outcome =
                payloadRecord == null
                    ? buildMissingTargetOutcome(sourceRecordId, config, submissionRecord)
                    : PublicApiStatusUpdateDeliveryService.sendStatusUpdate(http, payloadRecord, config);

            PublicApi_Webhook_Delivery__c deliveryRecord = PublicApiWebhookDeliveryRecordService.buildDeliveryRecord(
                configId,
                sourceRecordId,
                normalizePayloadObjectApiName(config),
                currentValue,
                config.statusUpdateWebhookUrl,
                outcome == null ? null : outcome.payloadJson,
                outcome == null ? buildFallbackDeliveryResult() : outcome.deliveryResult
            );
            if (deliveryRecord != null) {
                if (submissionRecord != null) {
                    deliveryRecord.Submission__c = submissionRecord.Id;
                }
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
            Id sourceRecordId = parseSourceRecordId(requestEvent);
            if (sourceRecordId == null) {
                continue;
            }
            items.add(new PublicApiOutboundRequestQueueable.RequestItem(
                sourceRecordId,
                parseConfigId(requestEvent),
                requestEvent.Previous_Value__c,
                requestEvent.Current_Value__c,
                requestEvent.Changed_At__c
            ));
        }
        return items;
    }

    @TestVisible
    static Set<Id> getRequestConfigIds(List<PublicApiOutboundRequestQueueable.RequestItem> requests) {
        Set<Id> configIds = new Set<Id>();
        if (requests == null) {
            return configIds;
        }
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            if (requestItem != null && requestItem.configId != null) {
                configIds.add(requestItem.configId);
            }
        }
        return configIds;
    }

    @TestVisible
    static Id parseSourceRecordId(PublicApi_Outbound_Request__e requestEvent) {
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
    static Map<Id, SObject> queryPayloadRecords(
        List<PublicApiOutboundRequestQueueable.RequestItem> requests,
        Map<Id, PublicApiConfigService.Config> configsById
    ) {
        Map<String, Set<Id>> recordIdsByObject = new Map<String, Set<Id>>();
        Map<String, Set<Id>> configIdsByObject = new Map<String, Set<Id>>();
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            Id sourceRecordId = requestItem == null ? null : requestItem.sourceRecordId;
            Id configId = requestItem == null ? null : requestItem.configId;
            if (sourceRecordId == null || configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(configId);
            String payloadObjectApiName = normalizePayloadObjectApiName(config);
            if (config == null || String.isBlank(payloadObjectApiName)) {
                continue;
            }

            String objectApiName = payloadObjectApiName.trim();
            if (!recordIdsByObject.containsKey(objectApiName)) {
                recordIdsByObject.put(objectApiName, new Set<Id>());
            }
            recordIdsByObject.get(objectApiName).add(sourceRecordId);

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

    @TestVisible
    static Map<String, PublicApi_Submission__c> getSubmissionRecords(
        List<PublicApiOutboundRequestQueueable.RequestItem> requests,
        Map<Id, PublicApiConfigService.Config> configsById
    ) {
        Map<String, PublicApi_Submission__c> submissionsBySourceKey = new Map<String, PublicApi_Submission__c>();
        if (requests == null || requests.isEmpty() || configsById == null || configsById.isEmpty()) {
            return submissionsBySourceKey;
        }

        Set<Id> submissionIds = new Set<Id>();
        Set<Id> configIds = new Set<Id>();
        Map<Id, Set<Id>> sourceRecordIdsByConfig = new Map<Id, Set<Id>>();
        for (PublicApiOutboundRequestQueueable.RequestItem requestItem : requests) {
            if (requestItem == null || requestItem.sourceRecordId == null || requestItem.configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(requestItem.configId);
            if (config == null) {
                continue;
            }

            String payloadObjectApiName = normalizePayloadObjectApiName(config);
            if (payloadObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME) {
                submissionIds.add(requestItem.sourceRecordId);
                continue;
            }

            configIds.add(requestItem.configId);
            if (!sourceRecordIdsByConfig.containsKey(requestItem.configId)) {
                sourceRecordIdsByConfig.put(requestItem.configId, new Set<Id>());
            }
            sourceRecordIdsByConfig.get(requestItem.configId).add(requestItem.sourceRecordId);
        }

        if (!submissionIds.isEmpty()) {
            for (PublicApi_Submission__c submissionRecord : [
                SELECT Id, PublicApi_Integration_Config__c
                FROM PublicApi_Submission__c
                WHERE Id IN :submissionIds
            ]) {
                submissionsBySourceKey.put(
                    buildSourceKey(submissionRecord.PublicApi_Integration_Config__c, submissionRecord.Id),
                    submissionRecord
                );
            }
        }

        if (!configIds.isEmpty()) {
            for (PublicApi_Submission__c submissionRecord : [
                SELECT Id, PublicApi_Integration_Config__c, Target_Object_API_Name__c, Target_Record_Id__c, CreatedDate
                FROM PublicApi_Submission__c
                WHERE PublicApi_Integration_Config__c IN :configIds
                ORDER BY CreatedDate DESC
            ]) {
                Id parsedTargetRecordId = parseId(submissionRecord.Target_Record_Id__c);
                Set<Id> requestedSourceRecordIds = sourceRecordIdsByConfig.get(submissionRecord.PublicApi_Integration_Config__c);
                if (parsedTargetRecordId == null ||
                    requestedSourceRecordIds == null ||
                    !requestedSourceRecordIds.contains(parsedTargetRecordId)) {
                    continue;
                }
                String sourceKey = buildSourceKey(
                    submissionRecord.PublicApi_Integration_Config__c,
                    parsedTargetRecordId
                );
                if (String.isBlank(sourceKey) || submissionsBySourceKey.containsKey(sourceKey)) {
                    continue;
                }
                submissionsBySourceKey.put(sourceKey, submissionRecord);
            }
        }

        return submissionsBySourceKey;
    }

    @TestVisible
    static PublicApi_Submission__c resolveSubmissionRecord(
        PublicApiOutboundRequestQueueable.RequestItem requestItem,
        PublicApiConfigService.Config config,
        Map<String, PublicApi_Submission__c> submissionsBySourceKey
    ) {
        if (requestItem == null || requestItem.sourceRecordId == null || requestItem.configId == null) {
            return null;
        }

        String payloadObjectApiName = normalizePayloadObjectApiName(config);
        if (payloadObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME) {
            return new PublicApi_Submission__c(Id = requestItem.sourceRecordId);
        }

        if (submissionsBySourceKey == null) {
            return null;
        }
        return submissionsBySourceKey.get(buildSourceKey(requestItem.configId, requestItem.sourceRecordId));
    }

    @TestVisible
    static String buildSourceKey(Id configId, Id sourceRecordId) {
        if (configId == null || sourceRecordId == null) {
            return null;
        }
        return String.valueOf(configId) + ':' + String.valueOf(sourceRecordId);
    }

    @TestVisible
    static Id parseId(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        try {
            return (Id) rawValue.trim();
        } catch (Exception e) {
            return null;
        }
    }

    private static String normalizePayloadObjectApiName(PublicApiConfigService.Config config) {
        if (config == null || String.isBlank(config.targetObjectApiName)) {
            return PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME;
        }
        return config.targetObjectApiName.trim();
    }

    private static PublicApiStatusUpdateDeliveryService.SendOutcome buildMissingTargetOutcome(
        Id sourceRecordId,
        PublicApiConfigService.Config config,
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
            ', source record ' + String.valueOf(sourceRecordId) +
            ', and target object ' + normalizePayloadObjectApiName(config) + '.';
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
