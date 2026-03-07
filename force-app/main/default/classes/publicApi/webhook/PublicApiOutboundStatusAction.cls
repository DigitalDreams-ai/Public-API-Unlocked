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
        label='Enqueue Public API Outbound Status Update'
        description='Queues a Public API outbound webhook delivery for any configured source object.'
    )
    public static void enqueue(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<PublicApiOutboundTriggerService.StatusChangeRequest> normalizedRequests =
            new List<PublicApiOutboundTriggerService.StatusChangeRequest>();
        String sessionId = UserInfo.getSessionId();
        for (Request request : requests) {
            if (request == null || request.recordId == null || request.configId == null) {
                continue;
            }
            normalizedRequests.add(new PublicApiOutboundTriggerService.StatusChangeRequest(
                request.recordId,
                request.configId,
                request.previousStatus,
                request.currentStatus,
                request.changedAt,
                sessionId
            ));
        }
        PublicApiOutboundTriggerService.enqueueStatusChanges(normalizedRequests);
    }
}
