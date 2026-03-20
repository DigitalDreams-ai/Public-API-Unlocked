public with sharing class PublicApiSiteUrlService {
    @TestVisible static String baseUrlOverride;

    public static String getPublicSiteBaseUrl() {
        if (Test.isRunningTest() && String.isNotBlank(baseUrlOverride)) {
            return normalizeBaseUrl(baseUrlOverride);
        }

        String domain = resolveSalesforceSitesDomain();
        if (String.isBlank(domain)) {
            return System.Url.getOrgDomainUrl().toExternalForm();
        }

        String baseUrl = 'https://' + domain;
        String pathPrefix = resolvePreferredPathPrefix();
        if (String.isNotBlank(pathPrefix)) {
            baseUrl += '/' + pathPrefix.trim();
        }
        return normalizeBaseUrl(baseUrl);
    }

    @TestVisible
    private static String resolveSalesforceSitesDomain() {
        List<Domain> domains = [
            SELECT Domain
            FROM Domain
            WHERE Domain LIKE '%.my.salesforce-sites.com'
            ORDER BY Domain
            LIMIT 1
        ];
        return domains.isEmpty() ? null : domains[0].Domain;
    }

    @TestVisible
    private static String resolvePreferredPathPrefix() {
        List<Site> sites = [
            SELECT Name, UrlPathPrefix
            FROM Site
            ORDER BY Name
        ];

        String fallbackPrefix;
        for (Site siteRecord : sites) {
            String pathPrefix = siteRecord.UrlPathPrefix == null ? null : siteRecord.UrlPathPrefix.trim();
            if (String.isBlank(pathPrefix)) {
                continue;
            }
            if (pathPrefix.toLowerCase() == 'api') {
                return pathPrefix;
            }
            if (String.isBlank(fallbackPrefix)) {
                fallbackPrefix = pathPrefix;
            }
        }
        return fallbackPrefix;
    }

    @TestVisible
    private static String normalizeBaseUrl(String baseUrl) {
        if (String.isBlank(baseUrl)) {
            return null;
        }
        String normalized = baseUrl.trim();
        while (normalized.endsWith('/')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized;
    }
}
