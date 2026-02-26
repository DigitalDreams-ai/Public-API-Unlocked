/**
 * Applies Unbounce_Field_Mapping__c JSON templates to incoming payloads (e.g. Unbounce).
 * Uses the Unbounce-specific object only; does not use Shulman API Custom_Mapping__c.
 * Template format: keys define output shape; values like $.path resolve from the payload.
 */
public with sharing class UnbounceCustomMappingService {

    private static final String CONTEXT_UNBOUNCE_INTAKE = 'Unbounce Intake';

    /**
     * If an active Unbounce Field Mapping exists for Unbounce Intake, transforms the payload
     * using its Mapping_Configuration__c JSON template ($.path references resolve from payload).
     * Returns the transformed map; otherwise returns the original payload unchanged.
     */
    public static Map<String, Object> applyMapping(Map<String, Object> payload) {
        if (payload == null) {
            return payload;
        }

        Unbounce_Field_Mapping__c mapping = getActiveMapping();
        if (mapping == null || String.isBlank(mapping.Mapping_Configuration__c)) {
            return payload;
        }

        try {
            Map<String, Object> template = (Map<String, Object>) JSON.deserializeUntyped(mapping.Mapping_Configuration__c);
            Map<String, Object> result = resolveTemplate(template, payload);
            return result != null ? result : payload;
        } catch (JSONException e) {
            return payload;
        }
    }

    private static Unbounce_Field_Mapping__c getActiveMapping() {
        List<Unbounce_Field_Mapping__c> mappings = [
            SELECT Id, Mapping_Configuration__c
            FROM Unbounce_Field_Mapping__c
            WHERE Is_Active__c = true
            AND (Context__c = :CONTEXT_UNBOUNCE_INTAKE OR Context__c = null)
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return mappings.isEmpty() ? null : mappings[0];
    }

    /**
     * Resolves a JSON template against a source payload.
     * Leaf string values starting with "$." are resolved from sourcePayload; others are literal.
     */
    @TestVisible
    private static Map<String, Object> resolveTemplate(Map<String, Object> template, Map<String, Object> sourcePayload) {
        if (template == null) {
            return null;
        }
        Map<String, Object> result = new Map<String, Object>();
        for (String key : template.keySet()) {
            Object value = resolveValue(template.get(key), sourcePayload);
            if (value != null) {
                result.put(key, value);
            }
        }
        return result;
    }

    private static Object resolveValue(Object value, Map<String, Object> sourcePayload) {
        if (value == null) {
            return null;
        }
        if (value instanceof String) {
            String str = (String) value;
            if (str.startsWith('$.')) {
                return getValueAtPath(sourcePayload, str.substring(2));
            }
            return str;
        }
        if (value instanceof Map<String, Object>) {
            return resolveTemplate((Map<String, Object>) value, sourcePayload);
        }
        return value;
    }

    @TestVisible
    private static Object getValueAtPath(Map<String, Object> payload, String path) {
        if (String.isBlank(path)) {
            return null;
        }
        List<String> parts = path.split('\\.');
        Object current = payload;
        for (String part : parts) {
            if (part == null || part.trim().length() == 0) {
                continue;
            }
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            current = ((Map<String, Object>) current).get(part.trim());
            if (current == null) {
                return null;
            }
        }
        return current;
    }
}
