/**
 * Model class for mapping Unbounce webhook payload to litify_pm__Intake__c.
 * Mapping follows: URL→lit_Exact_Source; name→First_Name; last_name→Last_Name;
 * phone_number→Phone_Mobile; email→Email; how_can_we_help_you→Description;
 * utm_source→UTM_Source; gclid→ExternalId; utm_medium→UTM_Medium.
 */
public with sharing class UnbounceIntakeModel {

    /**
     * Maps Unbounce webhook payload to litify_pm__Intake__c.
     * Supports Unbounce field names per mapping table and a flexible data wrapper.
     *
     * @param payload Untyped map from Unbounce webhook (e.g. data.name, data.email, data.how_can_we_help_you)
     * @return Intake record ready for insert
     */
    public static litify_pm__Intake__c fromUnbouncePayload(Map<String, Object> payload) {
        if (payload == null) {
            throw new UnbounceIntakeServiceException('Payload cannot be null');
        }

        Map<String, Object> data = extractDataMap(payload);
        litify_pm__Intake__c intake = new litify_pm__Intake__c();

        // Party/contact fields (mapped to Intake)
        intake.litify_pm__First_Name__c = getString(data, new List<String>{ 'name', 'first_name', 'First_name', 'firstName', 'firstname' });
        intake.litify_pm__Last_Name__c = getString(data, new List<String>{ 'last_name', 'Last_name', 'lastName', 'lastname' });
        intake.litify_pm__Email__c = getString(data, new List<String>{ 'email', 'Email', 'email_address' });
        String phone = getString(data, new List<String>{ 'phone_number', 'phone', 'Phone', 'telephone' });
        intake.litify_pm__Phone__c = phone;
        setOptionalField(intake, 'litify_pm__Phone_Mobile__c', phone);

        // Address
        intake.litify_pm__Case_Address_1__c = getString(data, new List<String>{ 'address', 'address1', 'street', 'case_address_1' });
        intake.litify_pm__Case_Address_2__c = getString(data, new List<String>{ 'address2', 'address_2' });
        intake.litify_pm__Case_City__c = getString(data, new List<String>{ 'city', 'City' });
        intake.litify_pm__Case_State__c = getString(data, new List<String>{ 'state', 'State', 'province' });
        intake.litify_pm__Case_Postal_Code__c = getString(data, new List<String>{ 'zip', 'zip_code', 'postal_code', 'postalcode' });

        // Intake fields
        intake.litify_pm__Description__c = getString(data, new List<String>{ 'how_can_we_help_you', 'description', 'message', 'comments', 'notes' });
        setOptionalField(intake, 'litify_pm__lit_Exact_Source__c', getString(data, new List<String>{ 'URL', 'url' }));

        // Only set when payload provides value; org may have Source__c as text or lookup
        String source = getString(data, new List<String>{ 'source' });
        setOptionalField(intake, 'litify_pm__Source__c', source);
        setOptionalField(intake, 'litify_pm__UTM_Source__c', getString(data, new List<String>{ 'utm_source' }));
        setOptionalField(intake, 'litify_pm__UTM_Medium__c', getString(data, new List<String>{ 'utm_medium' }));

        String sourceType = getString(data, new List<String>{ 'source_type', 'sourceType', 'source type' });
        if (String.isBlank(sourceType)) {
            sourceType = 'Advertising';
        }
        setOptionalField(intake, 'litify_pm__Source_Type__c', sourceType);

        String externalId = getString(data, new List<String>{ 'gclid', 'submission_id', 'submissionId', 'id', 'external_id' });
        if (String.isNotBlank(externalId)) {
            setOptionalField(intake, 'ExternalId__c', externalId);
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

    private static void setOptionalField(litify_pm__Intake__c intake, String fieldName, String value) {
        if (String.isBlank(value)) return;
        try {
            intake.put(fieldName, value);
        } catch (Exception e) {
            // Field may not exist or may be wrong type (e.g. lookup that rejects text)
        }
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
