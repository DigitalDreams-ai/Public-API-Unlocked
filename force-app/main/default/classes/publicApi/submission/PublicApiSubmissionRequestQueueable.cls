public without sharing class PublicApiSubmissionRequestQueueable implements Queueable {
    @TestVisible static final Integer MAX_SUBMISSIONS_PER_JOB = 90;

    private List<Id> submissionIds;

    public PublicApiSubmissionRequestQueueable(List<Id> submissionIds) {
        this.submissionIds = submissionIds == null ? new List<Id>() : new List<Id>(submissionIds);
    }

    public static void enqueue(List<Id> submissionIds) {
        if (submissionIds == null || submissionIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new PublicApiSubmissionRequestQueueable(submissionIds));
    }

    public void execute(QueueableContext context) {
        if (submissionIds == null || submissionIds.isEmpty()) {
            return;
        }

        List<Id> currentBatch = takeBatch(submissionIds);
        List<Id> remaining = dropBatch(submissionIds);
        if (!currentBatch.isEmpty()) {
            PublicApiSubmissionRequestEventService.processSubmissionIds(currentBatch);
        }
        if (!remaining.isEmpty()) {
            System.enqueueJob(new PublicApiSubmissionRequestQueueable(remaining));
        }
    }

    @TestVisible
    static List<Id> takeBatch(List<Id> sourceIds) {
        List<Id> batch = new List<Id>();
        if (sourceIds == null || sourceIds.isEmpty()) {
            return batch;
        }

        Integer limitSize = Math.min(MAX_SUBMISSIONS_PER_JOB, sourceIds.size());
        for (Integer index = 0; index < limitSize; index++) {
            if (sourceIds[index] != null) {
                batch.add(sourceIds[index]);
            }
        }
        return batch;
    }

    @TestVisible
    static List<Id> dropBatch(List<Id> sourceIds) {
        List<Id> remaining = new List<Id>();
        if (sourceIds == null || sourceIds.size() <= MAX_SUBMISSIONS_PER_JOB) {
            return remaining;
        }

        for (Integer index = MAX_SUBMISSIONS_PER_JOB; index < sourceIds.size(); index++) {
            if (sourceIds[index] != null) {
                remaining.add(sourceIds[index]);
            }
        }
        return remaining;
    }
}
