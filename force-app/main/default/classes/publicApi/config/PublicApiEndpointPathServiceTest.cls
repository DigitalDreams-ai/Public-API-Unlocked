@IsTest
private class PublicApiEndpointPathServiceTest {
    @IsTest
    static void testNormalizeConfiguredPath() {
        System.assertEquals('/submissions', PublicApiEndpointPathService.normalizeConfiguredPath(null));
        System.assertEquals('/intake', PublicApiEndpointPathService.normalizeConfiguredPath(' intake '));
        System.assertEquals('/partner/leads', PublicApiEndpointPathService.normalizeConfiguredPath('//Partner//Leads/'));
    }

    @IsTest
    static void testExtractRequestEndpointPath() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/v1/publicapi/Partner/Leads/';
        System.assertEquals('/partner/leads', PublicApiEndpointPathService.extractRequestEndpointPath(request));
    }

    @IsTest
    static void testNormalizeConfiguredPathRejectsInvalidCharacters() {
        try {
            PublicApiEndpointPathService.normalizeConfiguredPath('/bad path');
            System.assert(false, 'Expected endpoint normalization to reject spaces.');
        } catch (PublicApiSubmissionServiceException e) {
            System.assert(e.getMessage().contains('Endpoint path may contain only'));
        }
    }
}
