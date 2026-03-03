public without sharing class UnbounceIntakeTrackingService {

    public static void trackIntake(Id intakeId, Id configId) {
        if (intakeId == null) {
            throw new UnbounceIntakeServiceException('Cannot track an intake without an intake id.');
        }
        if (configId == null) {
            throw new UnbounceIntakeServiceException('Cannot track an intake without an Unbounce Integration Config id.');
        }

        upsert new Unbounce_Intake_Tracking__c(
            Intake_Id__c = String.valueOf(intakeId),
            Unbounce_Integration_Config__c = configId
        ) Intake_Id__c;
    }

    public static Map<Id, Unbounce_Intake_Tracking__c> getTrackingByIntakeId(Set<Id> intakeIds) {
        Map<Id, Unbounce_Intake_Tracking__c> trackingByIntakeId = new Map<Id, Unbounce_Intake_Tracking__c>();
        if (intakeIds == null || intakeIds.isEmpty()) {
            return trackingByIntakeId;
        }

        Set<String> intakeIdValues = new Set<String>();
        for (Id intakeId : intakeIds) {
            if (intakeId != null) {
                intakeIdValues.add(String.valueOf(intakeId));
            }
        }
        if (intakeIdValues.isEmpty()) {
            return trackingByIntakeId;
        }

        for (Unbounce_Intake_Tracking__c tracking : [
            SELECT Id, Intake_Id__c, Unbounce_Integration_Config__c
            FROM Unbounce_Intake_Tracking__c
            WHERE Intake_Id__c IN :intakeIdValues
        ]) {
            Id trackedIntakeId = parseId(tracking.Intake_Id__c);
            if (trackedIntakeId != null) {
                trackingByIntakeId.put(trackedIntakeId, tracking);
            }
        }
        return trackingByIntakeId;
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value.trim();
        } catch (Exception e) {
            return null;
        }
    }
}
