public with sharing class UnbouncePayloadTemplateService {
    @TestVisible
    private static final Map<String, Object> DEFAULT_TEMPLATE_SCHEMA = new Map<String, Object>{
        'firstName' => '$.firstName',
        'lastName' => '$.lastName',
        'email' => '$.email',
        'gclid' => '$.gclid',
        'conversionTime' => '$.conversionTime',
        'createdDate' => '$.createdDate'
    };

    public static Map<String, Object> getDefaultTemplateSchema() {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(DEFAULT_TEMPLATE_SCHEMA));
    }

    public static Map<String, Object> applyTemplateConfiguration(
        String configJson,
        Map<String, Object> sourcePayload
    ) {
        if (sourcePayload == null) {
            return null;
        }
        if (String.isBlank(configJson)) {
            return clonePayload(sourcePayload);
        }

        Object parsed = JSON.deserializeUntyped(configJson);
        if (!(parsed instanceof Map<String, Object>)) {
            throw new UnbounceIntakeServiceException(
                'Outbound payload configuration must be a JSON object.'
            );
        }

        return resolveTemplate((Map<String, Object>) parsed, sourcePayload);
    }

    @TestVisible
    private static Map<String, Object> resolveTemplate(
        Map<String, Object> template,
        Map<String, Object> sourcePayload
    ) {
        Map<String, Object> result = new Map<String, Object>();
        if (template == null) {
            return result;
        }

        for (String key : template.keySet()) {
            result.put(key, resolveValue(template.get(key), sourcePayload));
        }

        return result;
    }

    private static Object resolveValue(Object value, Map<String, Object> sourcePayload) {
        if (value == null) {
            return null;
        }
        if (value instanceof String) {
            String strValue = (String) value;
            if (strValue == '$') {
                return clonePayload(sourcePayload);
            }
            if (strValue.startsWith('$.')) {
                return getValue(sourcePayload, strValue.substring(2));
            }
            return strValue;
        }
        if (value instanceof Map<String, Object>) {
            return resolveTemplate((Map<String, Object>) value, sourcePayload);
        }
        if (value instanceof List<Object>) {
            List<Object> result = new List<Object>();
            for (Object item : (List<Object>) value) {
                result.add(resolveValue(item, sourcePayload));
            }
            return result;
        }
        return value;
    }

    @TestVisible
    private static Object getValue(Map<String, Object> payload, String path) {
        if (payload == null || String.isBlank(path)) {
            return null;
        }

        Object current = payload;
        for (String part : splitPath(path)) {
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            current = ((Map<String, Object>) current).get(part);
            if (current == null) {
                return null;
            }
        }

        return current;
    }

    private static List<String> splitPath(String path) {
        List<String> cleaned = new List<String>();
        for (String part : path.split('\\.')) {
            if (String.isNotBlank(part)) {
                cleaned.add(part.trim());
            }
        }
        return cleaned;
    }

    private static Map<String, Object> clonePayload(Map<String, Object> payload) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(payload));
    }
}
