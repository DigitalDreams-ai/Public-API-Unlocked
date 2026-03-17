public without sharing class PublicApiEndpointPathService {
    @TestVisible static final String APEX_REST_PREFIX = '/services/apexrest';
    @TestVisible static final String PUBLIC_API_ROUTE_PREFIX = '/v1/publicapi';
    @TestVisible public static final String DEFAULT_ENDPOINT_PATH = '/submissions';
    @TestVisible static final String ENDPOINT_PATH_PATTERN = '^/[a-z0-9/_-]+$';

    public static String normalizeConfiguredPath(String rawPath) {
        String candidate = String.isBlank(rawPath) ? DEFAULT_ENDPOINT_PATH : rawPath.trim();
        candidate = candidate.replace('\\', '/');

        Integer queryIndex = candidate.indexOf('?');
        if (queryIndex >= 0) {
            candidate = candidate.substring(0, queryIndex);
        }

        Integer fragmentIndex = candidate.indexOf('#');
        if (fragmentIndex >= 0) {
            candidate = candidate.substring(0, fragmentIndex);
        }

        candidate = candidate.trim().toLowerCase();
        if (!candidate.startsWith('/')) {
            candidate = '/' + candidate;
        }
        while (candidate.contains('//')) {
            candidate = candidate.replace('//', '/');
        }
        if (candidate.length() > 1 && candidate.endsWith('/')) {
            candidate = candidate.substring(0, candidate.length() - 1);
        }

        if (!Pattern.matches(ENDPOINT_PATH_PATTERN, candidate)) {
            throw new PublicApiSubmissionServiceException(
                'Endpoint path may contain only lowercase letters, numbers, hyphens, underscores, and slashes.'
            );
        }
        return candidate;
    }

    public static String getConfiguredEndpointUrlPath(String endpointPath) {
        return PUBLIC_API_ROUTE_PREFIX + normalizeConfiguredPath(endpointPath);
    }

    public static String extractRequestEndpointPath(RestRequest request) {
        if (request == null || String.isBlank(request.requestURI)) {
            return DEFAULT_ENDPOINT_PATH;
        }

        String requestUri = request.requestURI.trim();
        Integer apexRestIndex = requestUri.toLowerCase().indexOf(APEX_REST_PREFIX);
        if (apexRestIndex >= 0) {
            requestUri = requestUri.substring(apexRestIndex + APEX_REST_PREFIX.length());
        }

        Integer routeIndex = requestUri.toLowerCase().indexOf(PUBLIC_API_ROUTE_PREFIX);
        if (routeIndex < 0) {
            throw new PublicApiSubmissionServiceException('Requested endpoint does not match the Public API route prefix.');
        }

        String configuredPath = requestUri.substring(routeIndex + PUBLIC_API_ROUTE_PREFIX.length());
        return normalizeConfiguredPath(configuredPath);
    }
}
