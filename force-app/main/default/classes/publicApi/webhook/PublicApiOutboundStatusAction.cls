public without sharing class PublicApiOutboundStatusAction {
    public class Request {
        @InvocableVariable(required=true)
        public Id recordId;

        @InvocableVariable(required=true)
        public Id configId;

        @InvocableVariable
        public String previousStatus;

        @InvocableVariable(required=true)
        public String currentStatus;

        @InvocableVariable
        public Datetime changedAt;
    }

    @InvocableMethod(
        label='Publish Public API Outbound Request'
        description='Publishes a Public API outbound webhook request for the configured submission or target record.'
    )
    public static void enqueue(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<PublicApiOutboundTriggerService.ChangeRequest> normalizedRequests = normalizeRequests(requests);
        validateConfigBackedRequests(normalizedRequests);
        PublicApiOutboundTriggerService.enqueueFieldChanges(normalizedRequests);
    }

    @TestVisible
    static List<PublicApiOutboundTriggerService.ChangeRequest> normalizeRequests(List<Request> requests) {
        List<PublicApiOutboundTriggerService.ChangeRequest> normalizedRequests =
            new List<PublicApiOutboundTriggerService.ChangeRequest>();
        if (requests == null) {
            return normalizedRequests;
        }

        for (Request request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }
            normalizedRequests.add(new PublicApiOutboundTriggerService.ChangeRequest(
                request.recordId,
                request.configId,
                request.previousStatus,
                request.currentStatus,
                request.changedAt
            ));
        }
        return normalizedRequests;
    }

    @TestVisible
    static void validateConfigBackedRequests(List<PublicApiOutboundTriggerService.ChangeRequest> requests) {
        Set<Id> configIds = new Set<Id>();
        Set<Id> submissionIds = new Set<Id>();
        Set<String> targetRecordIds = new Set<String>();
        for (PublicApiOutboundTriggerService.ChangeRequest request : requests) {
            if (request != null && request.recordId != null && request.configId != null) {
                configIds.add(request.configId);
                submissionIds.add(request.recordId);
                targetRecordIds.add(String.valueOf(request.recordId));
            }
        }

        Map<Id, PublicApiConfigService.Config> configsById = PublicApiConfigService.getConfigsById(configIds);
        Map<String, PublicApi_Submission__c> submissionsByKey = new Map<String, PublicApi_Submission__c>();
        if (!configIds.isEmpty()) {
            for (PublicApi_Submission__c submissionRecord : [
                SELECT Id, PublicApi_Integration_Config__c, Target_Record_Id__c
                FROM PublicApi_Submission__c
                WHERE PublicApi_Integration_Config__c IN :configIds
                AND (Id IN :submissionIds OR Target_Record_Id__c IN :targetRecordIds)
            ]) {
                submissionsByKey.put(
                    PublicApiOutboundTriggerService.buildResolutionKey(
                        submissionRecord.PublicApi_Integration_Config__c,
                        submissionRecord.Id
                    ),
                    submissionRecord
                );
                if (String.isNotBlank(submissionRecord.Target_Record_Id__c)) {
                    submissionsByKey.put(
                        PublicApiOutboundTriggerService.buildResolutionKey(
                            submissionRecord.PublicApi_Integration_Config__c,
                            submissionRecord.Target_Record_Id__c
                        ),
                        submissionRecord
                    );
                }
            }
        }

        for (PublicApiOutboundTriggerService.ChangeRequest request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }

            PublicApiConfigService.Config config = configsById.get(request.configId);
            if (config == null) {
                throw new PublicApiSubmissionServiceException(
                    'Outbound request configId must reference an active Public API Integration Config.'
                );
            }

            String resolutionKey = config.targetObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
                ? PublicApiOutboundTriggerService.buildResolutionKey(request.configId, request.recordId)
                : PublicApiOutboundTriggerService.buildResolutionKey(request.configId, String.valueOf(request.recordId));
            if (!submissionsByKey.containsKey(resolutionKey)) {
                throw new PublicApiSubmissionServiceException(
                    config.targetObjectApiName == PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
                        ? 'Outbound request recordId must reference a PublicApi_Submission__c record linked to the configured Public API Integration Config.'
                        : 'Outbound request recordId must reference a target record linked to the configured Public API Integration Config.'
                );
            }
        }
    }
}
