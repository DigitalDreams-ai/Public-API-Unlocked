trigger UnbounceClientAccountRequestTrigger on Unbounce_Client_Account_Request__e (after insert) {
    UnbounceIntakeService.processClientAccountRequests(Trigger.New);
}
