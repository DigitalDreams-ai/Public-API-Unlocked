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
            setStringField(intake, 'litify_pm__First_Name__c', getFirstName(name));
            setStringField(intake, 'litify_pm__Last_Name__c', getLastName(name));
        } else {
            setStringField(intake, 'litify_pm__First_Name__c', name);
            setStringField(intake, 'litify_pm__Last_Name__c', lastName);
        }

        setStringField(intake, 'litify_pm__Email__c', getString(
            data,
            new List<String>{ 'email' }
        ));
        String phone = getString(
            data,
            new List<String>{ 'phone_number', 'phone' }
        );
        setStringField(intake, 'litify_pm__Phone__c', phone);

        // Intake fields
        setStringField(intake, 'litify_pm__Description__c', getString(
            data,
            new List<String>{ 'how_can_we_help_you', 'description' }
        ));
        setOptionalField(
            intake,
            'litify_pm__lit_Exact_Source__c',
            getString(data, new List<String>{ 'page_url' })
        );

        // UTM params
        setOptionalField(intake, 'litify_pm__UTM_Source__c', getString(data, new List<String>{ 'utm_source' }));
        setOptionalField(intake, 'litify_pm__UTM_Medium__c', getString(data, new List<String>{ 'utm_medium' }));
        setOptionalField(intake, 'litify_pm__UTM_Campaign__c', getString(data, new List<String>{ 'campaignid' }));
        setOptionalField(intake, 'litify_pm__UTM_Content__c', getString(data, new List<String>{ 'utm_content' }));
        setOptionalField(intake, 'GCLID__c', getString(data, new List<String>{ 'gclid' }));

        setOptionalField(intake, 'litify_pm__Source_Type__c', getDefaultSourceTypeValue());

        return intake;
    }

    private static void setOptionalField(litify_pm__Intake__c intake, String fieldName, String value) {
        if (String.isBlank(value) || !INTAKE_FIELDS.containsKey(fieldName)) {
            return;
        }
        try {
            intake.put(fieldName, clampToFieldLength(fieldName, value));
        } catch (Exception e) {
            // Field may exist but reject the assigned type/value.
        }
    }

    private static void setStringField(litify_pm__Intake__c intake, String fieldName, String value) {
        if (intake == null || String.isBlank(fieldName) || !INTAKE_FIELDS.containsKey(fieldName)) {
            return;
        }
        intake.put(fieldName, clampToFieldLength(fieldName, value));
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
            String normalizedValue = normalizeStringValue(val);
            if (String.isNotBlank(normalizedValue)) {
                return normalizedValue;
            }
        }
        return null;
    }

    private static String normalizeStringValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof List<Object>) {
            for (Object item : (List<Object>) value) {
                String normalizedItem = normalizeStringValue(item);
                if (String.isNotBlank(normalizedItem)) {
                    return normalizedItem;
                }
            }
            return null;
        }

        String normalized = String.valueOf(value);
        return String.isNotBlank(normalized) ? normalized.trim() : null;
    }

    @TestVisible
    private static String getDefaultSourceTypeValue() {
        if (!INTAKE_FIELDS.containsKey('litify_pm__Source_Type__c')) {
            return null;
        }

        List<Schema.PicklistEntry> entries =
            INTAKE_FIELDS.get('litify_pm__Source_Type__c').getDescribe().getPicklistValues();

        for (String preferredValue : new List<String>{ 'Advertising', 'Advertisement' }) {
            for (Schema.PicklistEntry entry : entries) {
                if (entry.isActive() && entry.getValue() == preferredValue) {
                    return preferredValue;
                }
            }
        }

        for (Schema.PicklistEntry entry : entries) {
            if (!entry.isActive() || entry.getValue() == null) {
                continue;
            }

            String normalizedValue = entry.getValue().toLowerCase();
            if (normalizedValue.startsWith('advert')) {
                return entry.getValue();
            }
        }

        return null;
    }

    @TestVisible
    private static String clampToFieldLength(String fieldName, String value) {
        if (String.isBlank(value) || String.isBlank(fieldName) || !INTAKE_FIELDS.containsKey(fieldName)) {
            return value;
        }

        try {
            Schema.DescribeFieldResult describe = INTAKE_FIELDS.get(fieldName).getDescribe();
            Integer maxLength = describe.getLength();
            if (maxLength != null && maxLength > 0 && value.length() > maxLength) {
                if (describe.getType() == Schema.DisplayType.Email) {
                    return clampEmailToFieldLength(value, maxLength);
                }
                return value.substring(0, maxLength);
            }
        } catch (Exception e) {
            return value;
        }
        return value;
    }

    private static String clampEmailToFieldLength(String value, Integer maxLength) {
        if (String.isBlank(value) || maxLength == null || maxLength <= 0 || value.length() <= maxLength) {
            return value;
        }

        Integer atIndex = value.indexOf('@');
        if (atIndex <= 0) {
            return value.substring(0, maxLength);
        }

        String domain = value.substring(atIndex);
        Integer maxLocalPartLength = maxLength - domain.length();
        if (maxLocalPartLength <= 0) {
            return value.substring(0, maxLength);
        }

        String localPart = value.substring(0, atIndex);
        if (localPart.length() > maxLocalPartLength) {
            localPart = localPart.substring(0, maxLocalPartLength);
        }
        return localPart + domain;
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
