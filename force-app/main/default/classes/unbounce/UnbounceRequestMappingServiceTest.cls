@IsTest
private class UnbounceRequestMappingServiceTest {
    @IsTest
    static void testGetDefaultDirection_IsBoth() {
        System.assertEquals(
            UnbounceRequestMappingService.DIRECTION_BOTH,
            UnbounceRequestMappingService.getDefaultDirection()
        );
    }

    @IsTest
    static void testGetAvailableFieldReferences_IncludesIntakePrefix() {
        List<String> references = UnbounceRequestMappingService.getAvailableFieldReferences();

        System.assert(references.size() > 0);
        for (String reference : references) {
            System.assertEquals(true, reference.startsWith('$intake.'));
        }
    }

    @IsTest
    static void testParseConfiguration_UsesInboundAndOutboundArrays() {
        UnbounceRequestMappingService.MappingConfiguration config =
            UnbounceRequestMappingService.parseConfiguration(
                '{' +
                    '"inbound":[{"externalKey":"tracking_id","value":"$intake.GCLID__c","sortOrder":1}],' +
                    '"outbound":[{"externalKey":"googleClickId","value":"$intake.GCLID__c","sortOrder":2}]' +
                '}'
            );

        System.assertEquals(1, config.inboundMappings.size());
        System.assertEquals(1, config.outboundMappings.size());
        System.assertEquals('tracking_id', config.inboundMappings[0].externalKey);
        System.assertEquals('$intake.GCLID__c', config.outboundMappings[0].value);
    }

    @IsTest
    static void testValidateMappings_RejectsUnknownFieldReference() {
        try {
            UnbounceRequestMappingService.validateMappings(
                '{"inbound":[{"externalKey":"bad","value":"$intake.Does_Not_Exist__c","sortOrder":1}],"outbound":[]}',
                UnbounceRequestMappingService.DIRECTION_BOTH
            );
            System.assert(false, 'Expected validation to fail.');
        } catch (UnbounceIntakeServiceException e) {
            System.assert(e.getMessage().contains('Unknown Intake field reference'));
        }
    }

    @IsTest
    static void testApplyInboundMappings_UsesConfigWhenInboundAllowed() {
        litify_pm__Intake__c intake = new litify_pm__Intake__c();
        Map<String, Object> payload = new Map<String, Object>{
            'preferred_language' => 'Spanish',
            'tracking_id' => 'abc-123'
        };

        UnbounceRequestMappingService.applyInboundMappings(
            intake,
            payload,
            '{' +
                '"inbound":[' +
                    '{"externalKey":"preferred_language","value":"$intake.litify_pm__Description__c","sortOrder":1},' +
                    '{"externalKey":"tracking_id","value":"$intake.GCLID__c","sortOrder":2}' +
                '],' +
                '"outbound":[]' +
            '}',
            UnbounceRequestMappingService.DIRECTION_INBOUND
        );

        System.assertEquals('Spanish', intake.litify_pm__Description__c);
        System.assertEquals('abc-123', intake.GCLID__c);
    }

    @IsTest
    static void testApplyInboundMappings_MirrorsWhenDirectionIsBoth() {
        litify_pm__Intake__c intake = new litify_pm__Intake__c();

        UnbounceRequestMappingService.applyInboundMappings(
            intake,
            new Map<String, Object>{ 'tracking_id' => 'abc-123' },
            '{' +
                '"inbound":[{"externalKey":"tracking_id","value":"$intake.GCLID__c","sortOrder":1}],' +
                '"outbound":[]' +
            '}',
            UnbounceRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('abc-123', intake.GCLID__c);
    }

    @IsTest
    static void testApplyInboundMappings_SkipsWhenOutboundOnly() {
        litify_pm__Intake__c intake = new litify_pm__Intake__c();

        UnbounceRequestMappingService.applyInboundMappings(
            intake,
            new Map<String, Object>{ 'tracking_id' => 'abc-123' },
            '{' +
                '"inbound":[{"externalKey":"tracking_id","value":"$intake.GCLID__c","sortOrder":1}],' +
                '"outbound":[]' +
            '}',
            UnbounceRequestMappingService.DIRECTION_OUTBOUND
        );

        System.assertEquals(null, intake.GCLID__c);
    }

    @IsTest
    static void testBuildOutboundPayload_UsesConfiguredRows() {
        litify_pm__Intake__c intake = new litify_pm__Intake__c(
            litify_pm__Email__c = 'builder@example.com',
            GCLID__c = 'gclid-123'
        );
        intake.put('Google_Ads_Conversion_Time__c', Datetime.newInstanceGmt(2026, 3, 4, 12, 30, 0));

        Map<String, Object> payload = UnbounceRequestMappingService.buildOutboundPayload(
            intake,
            '{' +
                '"inbound":[],' +
                '"outbound":[' +
                    '{"externalKey":"emailAddress","value":"$intake.litify_pm__Email__c","sortOrder":1},' +
                    '{"externalKey":"googleClickId","value":"$intake.GCLID__c","sortOrder":2},' +
                    '{"externalKey":"conversionTime","value":"$intake.Google_Ads_Conversion_Time__c","sortOrder":3}' +
                ']' +
            '}',
            UnbounceRequestMappingService.DIRECTION_OUTBOUND
        );

        System.assertEquals('builder@example.com', payload.get('emailAddress'));
        System.assertEquals('gclid-123', payload.get('googleClickId'));
        System.assertEquals('2026-03-04T12:30:00.000Z', payload.get('conversionTime'));
    }

    @IsTest
    static void testBuildOutboundPayload_MirrorsWhenDirectionIsBoth() {
        litify_pm__Intake__c intake = new litify_pm__Intake__c(
            litify_pm__Email__c = 'builder@example.com'
        );

        Map<String, Object> payload = UnbounceRequestMappingService.buildOutboundPayload(
            intake,
            '{' +
                '"inbound":[{"externalKey":"emailAddress","value":"$intake.litify_pm__Email__c","sortOrder":1}],' +
                '"outbound":[]' +
            '}',
            UnbounceRequestMappingService.DIRECTION_BOTH
        );

        System.assertEquals('builder@example.com', payload.get('emailAddress'));
    }

    @IsTest
    static void testBuildOutboundPayload_SkipsWhenInboundOnly() {
        litify_pm__Intake__c intake = new litify_pm__Intake__c(
            litify_pm__Email__c = 'builder@example.com'
        );

        Map<String, Object> payload = UnbounceRequestMappingService.buildOutboundPayload(
            intake,
            '{' +
                '"inbound":[{"externalKey":"emailAddress","value":"$intake.litify_pm__Email__c","sortOrder":1}],' +
                '"outbound":[]' +
            '}',
            UnbounceRequestMappingService.DIRECTION_INBOUND
        );

        System.assertEquals(0, payload.size());
    }
}
