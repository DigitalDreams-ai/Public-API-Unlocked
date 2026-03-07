public without sharing class PublicApiPayloadTemplateService {
    @TestVisible static final String SUBMISSION_OBJECT_API_NAME = 'PublicApi_Submission__c';
    @TestVisible static final String RECORD_REFERENCE_PREFIX = '$intakes.';

    @TestVisible
    static final List<PublicApiRequestMappingService.MappingConfig> DEFAULT_INBOUND_MAPPINGS =
        new List<PublicApiRequestMappingService.MappingConfig>{
            new PublicApiRequestMappingService.MappingConfig('name', '$intakes.First_Name__c', 10),
            new PublicApiRequestMappingService.MappingConfig('first_name', '$intakes.First_Name__c', 20),
            new PublicApiRequestMappingService.MappingConfig('last_name', '$intakes.Last_Name__c', 30),
            new PublicApiRequestMappingService.MappingConfig('email', '$intakes.Email__c', 40),
            new PublicApiRequestMappingService.MappingConfig('phone_number', '$intakes.Phone__c', 50),
            new PublicApiRequestMappingService.MappingConfig('phone', '$intakes.Phone__c', 60),
            new PublicApiRequestMappingService.MappingConfig('how_can_we_help_you', '$intakes.Description__c', 70),
            new PublicApiRequestMappingService.MappingConfig('description', '$intakes.Description__c', 80),
            new PublicApiRequestMappingService.MappingConfig('page_url', '$intakes.Page_URL__c', 90),
            new PublicApiRequestMappingService.MappingConfig('utm_source', '$intakes.UTM_Source__c', 100),
            new PublicApiRequestMappingService.MappingConfig('utm_medium', '$intakes.UTM_Medium__c', 110),
            new PublicApiRequestMappingService.MappingConfig('campaignid', '$intakes.Campaign_Id__c', 120),
            new PublicApiRequestMappingService.MappingConfig('utm_content', '$intakes.UTM_Content__c', 130),
            new PublicApiRequestMappingService.MappingConfig('gclid', '$intakes.GCLID__c', 140)
        };

    @TestVisible
    static final List<PublicApiRequestMappingService.MappingConfig> DEFAULT_OUTBOUND_MAPPINGS =
        new List<PublicApiRequestMappingService.MappingConfig>{
            new PublicApiRequestMappingService.MappingConfig('name', '$intakes.First_Name__c', 10),
            new PublicApiRequestMappingService.MappingConfig('last_name', '$intakes.Last_Name__c', 20),
            new PublicApiRequestMappingService.MappingConfig('email', '$intakes.Email__c', 30),
            new PublicApiRequestMappingService.MappingConfig('phone', '$intakes.Phone__c', 40),
            new PublicApiRequestMappingService.MappingConfig('gclid', '$intakes.GCLID__c', 50),
            new PublicApiRequestMappingService.MappingConfig('createdDate', '$intakes.CreatedDate', 60)
        };

    public static String getDefaultMappingsJson() {
        return JSON.serializePretty(toSerializableMap(getDefaultConfiguration()));
    }

    public static List<String> getAvailableFieldReferences() {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(SUBMISSION_OBJECT_API_NAME)) {
            return new List<String>();
        }

        List<String> references = new List<String>();
        Map<String, Schema.SObjectField> fieldMap =
            globalDescribe.get(SUBMISSION_OBJECT_API_NAME).getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>(fieldMap.keySet());
        fieldNames.sort();
        for (String fieldName : fieldNames) {
            references.add(RECORD_REFERENCE_PREFIX + fieldName);
        }
        references.add(RECORD_REFERENCE_PREFIX + 'CreatedDate');
        return references;
    }

    public static Boolean inferSyncInboundAndOutbound(String configJson) {
        if (String.isBlank(configJson)) {
            return true;
        }
        try {
            PublicApiRequestMappingService.MappingConfiguration config =
                PublicApiRequestMappingService.parseConfiguration(configJson);
            return areMappingsEquivalent(config.inboundMappings, config.outboundMappings);
        } catch (Exception e) {
            return false;
        }
    }

    private static PublicApiRequestMappingService.MappingConfiguration getDefaultConfiguration() {
        PublicApiRequestMappingService.MappingConfiguration config =
            new PublicApiRequestMappingService.MappingConfiguration();
        config.inboundMappings = cloneMappings(DEFAULT_INBOUND_MAPPINGS);
        config.outboundMappings = cloneMappings(DEFAULT_OUTBOUND_MAPPINGS);
        return config;
    }

    private static List<PublicApiRequestMappingService.MappingConfig> cloneMappings(
        List<PublicApiRequestMappingService.MappingConfig> mappings
    ) {
        List<PublicApiRequestMappingService.MappingConfig> cloned =
            new List<PublicApiRequestMappingService.MappingConfig>();
        if (mappings == null) {
            return cloned;
        }

        for (PublicApiRequestMappingService.MappingConfig mapping : mappings) {
            if (mapping == null) {
                continue;
            }
            cloned.add(
                new PublicApiRequestMappingService.MappingConfig(
                    mapping.externalKey,
                    mapping.value,
                    mapping.sortOrder
                )
            );
        }
        cloned.sort(new MappingSortComparator());
        return cloned;
    }

    private static Map<String, Object> toSerializableMap(
        PublicApiRequestMappingService.MappingConfiguration config
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('inbound', cloneMappings(config == null ? null : config.inboundMappings));
        payload.put('outbound', cloneMappings(config == null ? null : config.outboundMappings));
        return payload;
    }

    private static Boolean areMappingsEquivalent(
        List<PublicApiRequestMappingService.MappingConfig> left,
        List<PublicApiRequestMappingService.MappingConfig> right
    ) {
        List<PublicApiRequestMappingService.MappingConfig> safeLeft =
            left == null ? new List<PublicApiRequestMappingService.MappingConfig>() : left;
        List<PublicApiRequestMappingService.MappingConfig> safeRight =
            right == null ? new List<PublicApiRequestMappingService.MappingConfig>() : right;
        if (safeLeft.size() != safeRight.size()) {
            return false;
        }

        for (Integer index = 0; index < safeLeft.size(); index++) {
            PublicApiRequestMappingService.MappingConfig leftRow = safeLeft[index];
            PublicApiRequestMappingService.MappingConfig rightRow = safeRight[index];
            if (!String.valueOf(leftRow == null ? null : leftRow.externalKey)
                    .equalsIgnoreCase(String.valueOf(rightRow == null ? null : rightRow.externalKey))) {
                return false;
            }
            if (!String.valueOf(leftRow == null ? null : leftRow.value)
                    .equalsIgnoreCase(String.valueOf(rightRow == null ? null : rightRow.value))) {
                return false;
            }
        }
        return true;
    }

    private class MappingSortComparator implements Comparator<PublicApiRequestMappingService.MappingConfig> {
        public Integer compare(
            PublicApiRequestMappingService.MappingConfig left,
            PublicApiRequestMappingService.MappingConfig right
        ) {
            Integer leftOrder = left == null || left.sortOrder == null ? 2147483647 : left.sortOrder;
            Integer rightOrder = right == null || right.sortOrder == null ? 2147483647 : right.sortOrder;
            if (leftOrder != rightOrder) {
                return leftOrder < rightOrder ? -1 : 1;
            }
            String leftKey = left == null || left.externalKey == null ? '' : left.externalKey;
            String rightKey = right == null || right.externalKey == null ? '' : right.externalKey;
            return leftKey.toLowerCase().compareTo(rightKey.toLowerCase());
        }
    }
}
