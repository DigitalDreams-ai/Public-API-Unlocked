public class PublicApiRelatedRecordConfig {
    public class Rule {
        @AuraEnabled public String targetLookupField;
        @AuraEnabled public String relatedObjectApiName;
        @AuraEnabled public String matchFieldName;
        @AuraEnabled public String sourceKey;
        @AuraEnabled public Boolean createIfMissing;
        @AuraEnabled public String onMultipleMatches;
        @AuraEnabled public List<CreateFieldMapping> createMappings;
    }

    public class CreateFieldMapping {
        @AuraEnabled public String sourceKey;
        @AuraEnabled public String fieldName;
    }

    public static List<Rule> parseRules(String relatedRecordConfigurationJson) {
        List<Rule> rules = new List<Rule>();
        if (String.isBlank(relatedRecordConfigurationJson)) {
            return rules;
        }

        Object parsed = JSON.deserializeUntyped(relatedRecordConfigurationJson);
        if (!(parsed instanceof List<Object>)) {
            throw new PublicApiIntakeServiceException(
                'Related record configuration must be a JSON array of rule rows.'
            );
        }

        for (Object entry : (List<Object>) parsed) {
            if (!(entry instanceof Map<String, Object>)) {
                continue;
            }

            Rule rule = fromMap((Map<String, Object>) entry);
            if (rule != null) {
                rules.add(rule);
            }
        }
        return rules;
    }

    public static Set<String> getConfiguredSourceKeys(String relatedRecordConfigurationJson) {
        Set<String> keys = new Set<String>();
        for (Rule rule : parseRules(relatedRecordConfigurationJson)) {
            if (String.isNotBlank(rule.sourceKey)) {
                keys.add(rule.sourceKey.trim());
            }
            if (rule.createMappings == null) {
                continue;
            }
            for (CreateFieldMapping mapping : rule.createMappings) {
                if (mapping != null && String.isNotBlank(mapping.sourceKey)) {
                    keys.add(mapping.sourceKey.trim());
                }
            }
        }
        return keys;
    }

    public static String serializeRules(List<Rule> rules) {
        return (rules == null || rules.isEmpty()) ? null : JSON.serialize(rules);
    }

    private static Rule fromMap(Map<String, Object> entry) {
        if (entry == null) {
            return null;
        }

        Rule rule = new Rule();
        rule.targetLookupField = normalizeString(entry.get('targetLookupField'));
        rule.relatedObjectApiName = normalizeString(entry.get('relatedObjectApiName'));
        rule.matchFieldName = normalizeString(entry.get('matchFieldName'));
        rule.sourceKey = normalizeString(entry.get('sourceKey'));
        rule.createIfMissing = parseBoolean(entry.get('createIfMissing'));
        rule.onMultipleMatches = normalizeString(entry.get('onMultipleMatches'));
        rule.createMappings = parseCreateMappings(entry.get('createMappings'));

        if (String.isBlank(rule.targetLookupField) &&
            String.isBlank(rule.relatedObjectApiName) &&
            String.isBlank(rule.matchFieldName) &&
            String.isBlank(rule.sourceKey) &&
            (rule.createMappings == null || rule.createMappings.isEmpty())) {
            return null;
        }
        return rule;
    }

    private static List<CreateFieldMapping> parseCreateMappings(Object rawMappings) {
        List<CreateFieldMapping> mappings = new List<CreateFieldMapping>();
        if (!(rawMappings instanceof List<Object>)) {
            return mappings;
        }

        for (Object rawEntry : (List<Object>) rawMappings) {
            if (!(rawEntry instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> entry = (Map<String, Object>) rawEntry;
            CreateFieldMapping mapping = new CreateFieldMapping();
            mapping.sourceKey = normalizeString(entry.get('sourceKey'));
            mapping.fieldName = normalizeString(entry.get('fieldName'));
            if (String.isBlank(mapping.sourceKey) && String.isBlank(mapping.fieldName)) {
                continue;
            }
            mappings.add(mapping);
        }
        return mappings;
    }

    private static String normalizeString(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Boolean parseBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return String.valueOf(value).trim().toLowerCase() == 'true';
    }
}
