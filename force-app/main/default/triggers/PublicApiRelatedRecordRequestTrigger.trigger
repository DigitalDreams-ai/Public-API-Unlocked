trigger PublicApiRelatedRecordRequestTrigger on PublicApi_Related_Record_Request__e (after insert) {
    PublicApiRelatedRecordEventService.handleEvents(Trigger.new);
}
