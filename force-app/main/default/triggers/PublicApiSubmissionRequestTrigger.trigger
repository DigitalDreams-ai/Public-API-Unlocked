trigger PublicApiSubmissionRequestTrigger on PublicApi_Submission_Request__e (after insert) {
    PublicApiSubmissionRequestEventService.handleEvents(Trigger.new);
}
