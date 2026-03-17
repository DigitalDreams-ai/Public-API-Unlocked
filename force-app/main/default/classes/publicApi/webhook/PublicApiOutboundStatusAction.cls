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

        List<PublicApiOutboundTriggerService.ChangeRequest> normalizedRequests =
            new List<PublicApiOutboundTriggerService.ChangeRequest>();
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
        validateTargetBackedRequests(normalizedRequests);
        PublicApiOutboundTriggerService.enqueueFieldChanges(normalizedRequests);
    }

    @TestVisible
    static void validateTargetBackedRequests(List<PublicApiOutboundTriggerService.ChangeRequest> requests) {
        Set<Id> configIds = new Set<Id>();
        for (PublicApiOutboundTriggerService.ChangeRequest request : requests) {
            if (request != null && request.configId != null) {
                configIds.add(request.configId);
            }
        }

        Map<Id, PublicApiConfigService.Config> configsById =
            configIds.isEmpty() ? new Map<Id, PublicApiConfigService.Config>() : PublicApiConfigService.getConfigsById(configIds);

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

            String targetObjectApiName = String.isBlank(config.targetObjectApiName)
                ? PublicApiConfigService.DEFAULT_SUBMISSION_OBJECT_API_NAME
                : config.targetObjectApiName.trim();
            if (request.recordId.getSObjectType().getDescribe().getName() != targetObjectApiName) {
                throw new PublicApiSubmissionServiceException(
                    'Outbound request recordId must reference a ' + targetObjectApiName +
                    ' record for the selected Public API Integration Config.'
                );
            }
        }
    }
}
