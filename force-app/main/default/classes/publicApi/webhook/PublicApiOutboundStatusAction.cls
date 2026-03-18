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
        description='Publishes a Public API outbound webhook request for a Public API submission record.'
    )
    public static void enqueue(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<PublicApiOutboundTriggerService.ChangeRequest> normalizedRequests = normalizeRequests(requests);
        validateSubmissionBackedRequests(normalizedRequests);
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
    static void validateSubmissionBackedRequests(List<PublicApiOutboundTriggerService.ChangeRequest> requests) {
        Set<Id> submissionIds = new Set<Id>();
        for (PublicApiOutboundTriggerService.ChangeRequest request : requests) {
            if (request != null && request.recordId != null) {
                submissionIds.add(request.recordId);
            }
        }

        Map<Id, Id> linkedConfigIdBySubmissionId = new Map<Id, Id>();
        if (!submissionIds.isEmpty()) {
            for (PublicApi_Submission__c submissionRecord : [
                SELECT Id, PublicApi_Integration_Config__c
                FROM PublicApi_Submission__c
                WHERE Id IN :submissionIds
            ]) {
                linkedConfigIdBySubmissionId.put(submissionRecord.Id, submissionRecord.PublicApi_Integration_Config__c);
            }
        }

        for (PublicApiOutboundTriggerService.ChangeRequest request : requests) {
            if (request == null || request.recordId == null) {
                continue;
            }
            if (!linkedConfigIdBySubmissionId.containsKey(request.recordId) ||
                linkedConfigIdBySubmissionId.get(request.recordId) == null) {
                throw new PublicApiSubmissionServiceException(
                    'Outbound request recordId must reference a PublicApi_Submission__c record linked to a Public API Integration Config.'
                );
            }
            if (request.configId != null && linkedConfigIdBySubmissionId.get(request.recordId) != request.configId) {
                throw new PublicApiSubmissionServiceException(
                    'Outbound request configId must match the Public API Integration Config linked to the submission record.'
                );
            }
        }
    }
}
