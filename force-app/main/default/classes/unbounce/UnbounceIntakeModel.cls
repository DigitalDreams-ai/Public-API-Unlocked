/**
 * Model class for mapping Unbounce webhook payload to litify_pm__Intake__c.
 * Supports the configured canonical Unbounce keys and a data wrapper.
 */
public with sharing class UnbounceIntakeModel {
    private static final Map<String, Schema.SObjectField> INTAKE_FIELDS =
        litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();

    /**
     * Maps Unbounce webhook payload to litify_pm__Intake__c.
     * Supports Unbounce field names per mapping table and a data wrapper.
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
        String name = getString(
            data,
            new List<String>{ 'name', 'first_name' }
        );
        String lastName = getString(
            data,
            new List<String>{ 'last_name' }
        );
        if (String.isBlank(lastName) && looksLikeFullName(name)) {
            intake.litify_pm__First_Name__c = getFirstName(name);
            intake.litify_pm__Last_Name__c = getLastName(name);
        } else {
            intake.litify_pm__First_Name__c = name;
            intake.litify_pm__Last_Name__c = lastName;
        }

        intake.litify_pm__Email__c = getString(
            data,
            new List<String>{ 'email' }
        );
        String phone = getString(
            data,
            new List<String>{ 'phone_number', 'phone' }
        );
        intake.litify_pm__Phone__c = phone;

        // Intake fields
        intake.litify_pm__Description__c = getString(
            data,
            new List<String>{ 'how_can_we_help_you', 'description' }
        );
        setOptionalField(
            intake,
            'litify_pm__lit_Exact_Source__c',
            getString(data, new List<String>{ 'page_url' })
        );

        // Source / UTM params
        String source = getString(data, new List<String>{ 'source' });
        setOptionalField(intake, 'litify_pm__Source__c', source);
        setOptionalField(intake, 'litify_pm__UTM_Source__c', getString(data, new List<String>{ 'utm_source' }));
        setOptionalField(intake, 'litify_pm__UTM_Medium__c', getString(data, new List<String>{ 'utm_medium' }));
        setOptionalField(intake, 'litify_pm__UTM_Campaign__c', getString(data, new List<String>{ 'campaignid' }));
        setOptionalField(intake, 'litify_pm__UTM_Content__c', getString(data, new List<String>{ 'utm_content' }));

        intake.litify_pm__Source_Type__c = 'Advertising';

        return intake;
    }

    private static void setOptionalField(litify_pm__Intake__c intake, String fieldName, String value) {
        if (String.isBlank(value) || !INTAKE_FIELDS.containsKey(fieldName)) {
            return;
        }
        try {
            intake.put(fieldName, value);
        } catch (Exception e) {
            // Field may exist but reject the assigned type/value.
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

    private static Boolean looksLikeFullName(String name) {
        return String.isNotBlank(name) && name.contains(' ');
    }

    private static String getFirstName(String fullName) {
        List<String> parts = splitName(fullName);
        return parts.isEmpty() ? fullName : parts[0];
    }

    private static String getLastName(String fullName) {
        List<String> parts = splitName(fullName);
        return parts.size() > 1 ? parts[1] : null;
    }

    private static List<String> splitName(String fullName) {
        if (String.isBlank(fullName)) {
            return new List<String>();
        }
        List<String> rawParts = fullName.trim().split('\\s+');
        if (rawParts.size() <= 1) {
            return new List<String>{ fullName.trim() };
        }

        List<String> lastNameParts = new List<String>();
        for (Integer i = 1; i < rawParts.size(); i++) {
            lastNameParts.add(rawParts[i]);
        }
        return new List<String>{ rawParts[0], String.join(lastNameParts, ' ') };
    }
}
