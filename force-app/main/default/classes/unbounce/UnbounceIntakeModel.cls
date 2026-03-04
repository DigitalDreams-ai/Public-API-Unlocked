/**
 * Model class for mapping Unbounce webhook payload to litify_pm__Intake__c.
 * Field mappings are driven by the builder-managed request mapping configuration.
 */
public with sharing class UnbounceIntakeModel {
    private static final Map<String, Schema.SObjectField> INTAKE_FIELDS =
        litify_pm__Intake__c.SObjectType.getDescribe().fields.getMap();

    public static litify_pm__Intake__c fromUnbouncePayload(Map<String, Object> payload) {
        return fromUnbouncePayload(payload, null, UnbounceRequestMappingService.getDefaultDirection());
    }

    public static litify_pm__Intake__c fromUnbouncePayload(
        Map<String, Object> payload,
        String requestFieldMappingsConfiguration,
        String requestDirection
    ) {
        if (payload == null) {
            throw new UnbounceIntakeServiceException('Payload cannot be null');
        }

        litify_pm__Intake__c intake = new litify_pm__Intake__c();
        UnbounceRequestMappingService.applyInboundMappings(
            intake,
            payload,
            requestFieldMappingsConfiguration,
            requestDirection
        );
        return intake;
    }

    @TestVisible
    public static String getDefaultSourceTypeValue() {
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
}
