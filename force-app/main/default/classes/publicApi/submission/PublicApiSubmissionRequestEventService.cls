public without sharing class PublicApiSubmissionRequestEventService {
    @TestVisible static Boolean simulatePublishFailure = false;

    private class SubmissionConfigSnapshot {
        public Id configId;
        public String targetObjectApiName;
        public String targetRecordTypeDeveloperName;
        public String inboundPayloadConfiguration;
        public String relatedRecordConfiguration;
    }

    private class PendingTargetInsert {
        public Id submissionId;
        public String targetObjectApiName;
        public String relatedRecordConfiguration;
        public SObject targetRecord;

        public PendingTargetInsert(
            Id submissionId,
            String targetObjectApiName,
            String relatedRecordConfiguration,
            SObject targetRecord
        ) {
            this.submissionId = submissionId;
            this.targetObjectApiName = targetObjectApiName;
            this.relatedRecordConfiguration = relatedRecordConfiguration;
            this.targetRecord = targetRecord;
        }
    }

    public static void publishRequest(Id submissionRecordId) {
        if (submissionRecordId == null) {
            return;
        }

        try {
            if (Test.isRunningTest() && simulatePublishFailure) {
                throw new PublicApiSubmissionServiceException(
                    PublicApiSubmissionService.EVENT_PUBLISH_FAILURE_MESSAGE_PREFIX + 'Simulated publish failure.'
                );
            }

            Database.SaveResult publishResult = EventBus.publish(
                new PublicApi_Submission_Request__e(
                    Submission_Record_Id__c = String.valueOf(submissionRecordId)
                )
            );
            if (publishResult == null || !publishResult.isSuccess()) {
                String errorMessage = 'Unknown platform event publish failure.';
                if (publishResult != null && publishResult.getErrors() != null && !publishResult.getErrors().isEmpty()) {
                    errorMessage = publishResult.getErrors()[0].getMessage();
                }
                throw new PublicApiSubmissionServiceException(
                    PublicApiSubmissionService.EVENT_PUBLISH_FAILURE_MESSAGE_PREFIX + errorMessage
                );
            }
        } catch (PublicApiSubmissionServiceException e) {
            throw e;
        } catch (Exception e) {
            throw new PublicApiSubmissionServiceException(
                PublicApiSubmissionService.EVENT_PUBLISH_FAILURE_MESSAGE_PREFIX + e.getMessage()
            );
        }
    }

    public static void handleEvents(List<PublicApi_Submission_Request__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        processSubmissionIds(getSubmissionIds(events));
    }

    public static void processSubmissionIds(List<Id> submissionIds) {
        if (submissionIds == null || submissionIds.isEmpty()) {
            return;
        }

        Map<Id, PublicApi_Submission__c> submissionsById = getSubmissionRecordsById(submissionIds);
        List<SObject> targetUpdates = new List<SObject>();
        List<Id> targetUpdateSubmissionIds = new List<Id>();
        List<PendingTargetInsert> pendingInserts = new List<PendingTargetInsert>();
        List<PublicApi_Submission__c> auditUpdates = new List<PublicApi_Submission__c>();

        for (Id submissionId : submissionIds) {
            if (submissionId == null || !submissionsById.containsKey(submissionId)) {
                continue;
            }

            PublicApi_Submission__c submissionRecord = submissionsById.get(submissionId);
            try {
                SubmissionConfigSnapshot config = resolveConfig(submissionRecord);
                PublicApiSubmissionService.validateSubmissionProcessingConfiguration(
                    config.inboundPayloadConfiguration,
                    config.relatedRecordConfiguration,
                    config.targetObjectApiName
                );

                Map<String, Object> payload = PublicApiPayloadParser.parsePayload(
                    submissionRecord.Raw_Payload__c,
                    submissionRecord.Request_Content_Type__c
                );

                SObject targetRecord;
                if (config.targetObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME) {
                    targetRecord = submissionRecord;
                } else {
                    Schema.SObjectType targetObjectType = Schema.getGlobalDescribe().get(config.targetObjectApiName);
                    if (targetObjectType == null) {
                        throw new PublicApiSubmissionServiceException(
                            'Submission object not found: ' + config.targetObjectApiName
                        );
                    }
                    targetRecord = targetObjectType.newSObject();
                }

                PublicApiRecordTypeService.applyTargetRecordType(targetRecord, config.targetRecordTypeDeveloperName);
                PublicApiRequestMappingService.applyInboundMappings(
                    targetRecord,
                    payload,
                    config.inboundPayloadConfiguration,
                    config.targetObjectApiName
                );
                PublicApiRelatedRecordService.applyRelatedRecordRules(
                    targetRecord,
                    payload,
                    config.relatedRecordConfiguration
                );

                if (config.targetObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME) {
                    PublicApiSubmissionService.applySuccessAuditState(
                        (PublicApi_Submission__c) targetRecord,
                        config.targetObjectApiName,
                        submissionRecord.Id,
                        config.relatedRecordConfiguration
                    );
                    targetUpdates.add(targetRecord);
                    targetUpdateSubmissionIds.add(submissionRecord.Id);
                } else {
                    pendingInserts.add(
                        new PendingTargetInsert(
                            submissionRecord.Id,
                            config.targetObjectApiName,
                            config.relatedRecordConfiguration,
                            targetRecord
                        )
                    );
                }
            } catch (Exception e) {
                auditUpdates.add(buildFailureAuditUpdate(submissionRecord.Id, e));
            }
        }

        if (!targetUpdates.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(targetUpdates, false);
            for (Integer index = 0; index < updateResults.size(); index++) {
                if (!updateResults[index].isSuccess()) {
                    auditUpdates.add(
                        buildFailureAuditUpdate(
                            targetUpdateSubmissionIds[index],
                            updateResults[index].getErrors()[0].getMessage()
                        )
                    );
                }
            }
        }

        if (!pendingInserts.isEmpty()) {
            List<SObject> targetRecords = new List<SObject>();
            for (PendingTargetInsert pendingInsert : pendingInserts) {
                targetRecords.add(pendingInsert.targetRecord);
            }

            Database.SaveResult[] insertResults = Database.insert(targetRecords, false);
            for (Integer index = 0; index < insertResults.size(); index++) {
                PendingTargetInsert pendingInsert = pendingInserts[index];
                if (insertResults[index].isSuccess()) {
                    PublicApi_Submission__c auditUpdate = new PublicApi_Submission__c(Id = pendingInsert.submissionId);
                    PublicApiSubmissionService.applySuccessAuditState(
                        auditUpdate,
                        pendingInsert.targetObjectApiName,
                        insertResults[index].getId(),
                        pendingInsert.relatedRecordConfiguration
                    );
                    auditUpdates.add(auditUpdate);
                } else {
                    auditUpdates.add(
                        buildFailureAuditUpdate(
                            pendingInsert.submissionId,
                            insertResults[index].getErrors()[0].getMessage()
                        )
                    );
                }
            }
        }

        persistAuditUpdates(auditUpdates);
    }

    @TestVisible
    static List<Id> getSubmissionIds(List<PublicApi_Submission_Request__e> events) {
        List<Id> submissionIds = new List<Id>();
        if (events == null) {
            return submissionIds;
        }

        for (PublicApi_Submission_Request__e requestEvent : events) {
            Id submissionId = parseSubmissionId(requestEvent);
            if (submissionId != null) {
                submissionIds.add(submissionId);
            }
        }
        return submissionIds;
    }

    @TestVisible
    static Map<Id, PublicApi_Submission__c> getSubmissionRecords(List<PublicApi_Submission_Request__e> events) {
        return getSubmissionRecordsById(new List<Id>(new Set<Id>(getSubmissionIds(events))));
    }

    @TestVisible
    static Map<Id, PublicApi_Submission__c> getSubmissionRecordsById(List<Id> submissionIds) {
        Map<Id, PublicApi_Submission__c> submissionsById = new Map<Id, PublicApi_Submission__c>();
        if (submissionIds == null || submissionIds.isEmpty()) {
            return submissionsById;
        }

        for (PublicApi_Submission__c submissionRecord : [
            SELECT Id,
                   PublicApi_Integration_Config__c,
                   Raw_Payload__c,
                   Request_Content_Type__c,
                   Effective_Config_JSON__c
            FROM PublicApi_Submission__c
            WHERE Id IN :submissionIds
        ]) {
            submissionsById.put(submissionRecord.Id, submissionRecord);
        }
        return submissionsById;
    }

    @TestVisible
    static SubmissionConfigSnapshot resolveConfig(PublicApi_Submission__c submissionRecord) {
        SubmissionConfigSnapshot snapshot = parseEffectiveConfig(submissionRecord);
        if (snapshot != null &&
            String.isNotBlank(snapshot.targetObjectApiName) &&
            String.isNotBlank(snapshot.inboundPayloadConfiguration)) {
            return snapshot;
        }

        PublicApiConfigService.Config liveConfig =
            PublicApiConfigService.getConfigById(submissionRecord.PublicApi_Integration_Config__c);
        if (liveConfig == null) {
            throw new PublicApiSubmissionServiceException(
                'Public API submission requires a matching active Public API Integration Config record.'
            );
        }

        SubmissionConfigSnapshot liveSnapshot = new SubmissionConfigSnapshot();
        liveSnapshot.configId = liveConfig.id;
        liveSnapshot.targetObjectApiName = String.isBlank(liveConfig.targetObjectApiName)
            ? PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
            : liveConfig.targetObjectApiName.trim();
        liveSnapshot.targetRecordTypeDeveloperName = liveConfig.targetRecordTypeDeveloperName;
        liveSnapshot.inboundPayloadConfiguration = liveConfig.inboundPayloadConfiguration;
        liveSnapshot.relatedRecordConfiguration = liveConfig.relatedRecordConfiguration;
        return liveSnapshot;
    }

    @TestVisible
    static SubmissionConfigSnapshot parseEffectiveConfig(PublicApi_Submission__c submissionRecord) {
        if (submissionRecord == null || String.isBlank(submissionRecord.Effective_Config_JSON__c)) {
            return null;
        }

        Object parsed = JSON.deserializeUntyped(submissionRecord.Effective_Config_JSON__c);
        if (!(parsed instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> values = (Map<String, Object>) parsed;
        SubmissionConfigSnapshot snapshot = new SubmissionConfigSnapshot();
        snapshot.configId = parseId(values.get('configId'));
        snapshot.targetObjectApiName = normalizeString(values.get('targetObjectApiName'));
        snapshot.targetRecordTypeDeveloperName = normalizeString(values.get('targetRecordTypeDeveloperName'));
        snapshot.inboundPayloadConfiguration = normalizeString(values.get('inboundPayloadConfiguration'));
        snapshot.relatedRecordConfiguration = normalizeString(values.get('relatedRecordConfiguration'));
        return snapshot;
    }

    @TestVisible
    static Id parseSubmissionId(PublicApi_Submission_Request__e requestEvent) {
        return requestEvent == null ? null : parseId(requestEvent.Submission_Record_Id__c);
    }

    private static PublicApi_Submission__c buildFailureAuditUpdate(Id submissionId, Exception e) {
        String errorMessage = e == null ? null : e.getMessage();
        String errorCategory = PublicApiSubmissionService.ERROR_CATEGORY_CONFIGURATION;
        if (e instanceof DmlException) {
            errorCategory = PublicApiSubmissionService.ERROR_CATEGORY_TARGET_DML;
        } else if (String.isNotBlank(errorMessage) &&
            (errorMessage.startsWith('Invalid JSON:') || errorMessage.startsWith('Invalid form-encoded payload'))) {
            errorCategory = PublicApiSubmissionService.ERROR_CATEGORY_PAYLOAD;
        } else if (String.isNotBlank(errorMessage) && errorMessage.startsWith('Failed to create related ')) {
            errorCategory = PublicApiSubmissionService.ERROR_CATEGORY_TARGET_DML;
        }
        return buildFailureAuditUpdate(
            submissionId,
            errorCategory,
            errorMessage
        );
    }

    private static PublicApi_Submission__c buildFailureAuditUpdate(Id submissionId, String errorMessage) {
        return buildFailureAuditUpdate(
            submissionId,
            PublicApiSubmissionService.ERROR_CATEGORY_TARGET_DML,
            errorMessage
        );
    }

    private static PublicApi_Submission__c buildFailureAuditUpdate(
        Id submissionId,
        String errorCategory,
        String errorMessage
    ) {
        if (submissionId == null) {
            return null;
        }

        return new PublicApi_Submission__c(
            Id = submissionId,
            Processing_Status__c = PublicApiSubmissionService.AUDIT_STATUS_FAILED,
            Processing_Error_Category__c = errorCategory,
            Processing_Error_Message__c = errorMessage
        );
    }

    private static void persistAuditUpdates(List<PublicApi_Submission__c> auditUpdates) {
        List<PublicApi_Submission__c> filteredUpdates = new List<PublicApi_Submission__c>();
        for (PublicApi_Submission__c auditUpdate : auditUpdates) {
            if (auditUpdate != null && auditUpdate.Id != null) {
                filteredUpdates.add(auditUpdate);
            }
        }
        if (!filteredUpdates.isEmpty()) {
            Database.update(filteredUpdates, false);
        }
    }

    private static Id parseId(Object value) {
        String normalizedValue = normalizeString(value);
        if (String.isBlank(normalizedValue)) {
            return null;
        }
        try {
            return (Id) normalizedValue;
        } catch (Exception e) {
            return null;
        }
    }

    private static String normalizeString(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }
}

