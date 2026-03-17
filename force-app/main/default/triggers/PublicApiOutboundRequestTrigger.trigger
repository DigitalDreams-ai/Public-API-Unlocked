trigger PublicApiOutboundRequestTrigger on PublicApi_Outbound_Request__e (after insert) {
    PublicApiOutboundRequestEventService.handleEvents(Trigger.new);
}
