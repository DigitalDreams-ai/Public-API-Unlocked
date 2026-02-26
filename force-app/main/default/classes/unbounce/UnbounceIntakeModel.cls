/**
 * Model class for mapping Unbounce webhook payload to litify_pm__Intake__c.
 * Unbounce sends form fields with flexible naming (e.g. first_name, First_name, email).
 */
public with sharing class UnbounceIntakeModel {

    /**
     * Maps Unbounce webhook payload to litify_pm__Intake__c.
     * Supports common Unbounce field names and a flexible data wrapper.
     *
     * @param payload Untyped map from Unbounce webhook (e.g. data.first_name, data.email)
     * @return Intake record ready for insert
     */
    public static litify_pm__Intake__c fromUnbouncePayload(Map<String, Object> payload) {
        if (payload == null) {
            throw new UnbounceIntakeServiceException('Payload cannot be null');
        }

        Map<String, Object> data = extractDataMap(payload);
        litify_pm__Intake__c intake = new litify_pm__Intake__c();

        intake.litify_pm__First_Name__c = getString(data, new List<String>{ 'first_name', 'First_name', 'firstName', 'firstname' });
        intake.litify_pm__Last_Name__c = getString(data, new List<String>{ 'last_name', 'Last_name', 'lastName', 'lastname' });
        intake.litify_pm__Email__c = getString(data, new List<String>{ 'email', 'Email', 'email_address' });
        intake.litify_pm__Phone__c = getString(data, new List<String>{ 'phone', 'Phone', 'phone_number', 'telephone' });

        intake.litify_pm__Case_Address_1__c = getString(data, new List<String>{ 'address', 'address1', 'street', 'case_address_1' });
        intake.litify_pm__Case_Address_2__c = getString(data, new List<String>{ 'address2', 'address_2' });
        intake.litify_pm__Case_City__c = getString(data, new List<String>{ 'city', 'City' });
        intake.litify_pm__Case_State__c = getString(data, new List<String>{ 'state', 'State', 'province' });
        intake.litify_pm__Case_Postal_Code__c = getString(data, new List<String>{ 'zip', 'zip_code', 'postal_code', 'postalcode' });

        intake.litify_pm__Description__c = getString(data, new List<String>{ 'description', 'message', 'comments', 'notes' });
        intake.litify_pm__Source__c = getString(data, new List<String>{ 'source', 'utm_source' });
        intake.litify_pm__Source_Type__c = 'Unbounce';

        String externalId = getString(data, new List<String>{ 'submission_id', 'submissionId', 'id', 'external_id' });
        if (String.isNotBlank(externalId)) {
            try {
                intake.put('ExternalId__c', externalId);
            } catch (SObjectException e) {
                // Field may not exist in org
            }
        }
        if (!data.isEmpty()) {
            try {
                intake.put('Additional_Metadata__c', JSON.serialize(data));
            } catch (SObjectException e) {
                // Field may not exist in org
            }
        }

        return intake;
    }

    private static Map<String, Object> extractDataMap(Map<String, Object> payload) {
        if (payload.containsKey('data') && payload.get('data') instanceof Map<String, Object>) {
            return (Map<String, Object>) payload.get('data');
        }
        return payload;
    }

    private static String getString(Map<String, Object> data, List<String> keys) {
        for (String key : keys) {
            Object val = data.get(key);
            if (val != null && String.isNotBlank(String.valueOf(val))) {
                return String.valueOf(val).trim();
            }
        }
        return null;
    }
}
