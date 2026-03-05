public with sharing class PublicApiRemoteSiteSettingService {
    private static final String METADATA_API_ENDPOINT = '/services/Soap/m/61.0';
    private static final String REMOTE_SITE_NAME_PREFIX = 'PublicApiWebhook_';

    public static String ensureStatusWebhookRemoteSite(String webhookUrl) {
        return ensureStatusWebhookRemoteSite(webhookUrl, null);
    }

    public static String ensureStatusWebhookRemoteSite(String webhookUrl, String sessionId) {
        if (String.isBlank(webhookUrl)) {
            return null;
        }

        String domainUrl = extractDomainFromUrl(webhookUrl);
        if (String.isBlank(domainUrl)) {
            throw new PublicApiRemoteSiteSettingException(
                'Unable to extract a domain from the PublicApi status webhook URL.'
            );
        }

        String fullName = generateRemoteSiteSettingName(domainUrl);
        return createRemoteSiteSetting(
            fullName,
            domainUrl,
            'Remote Site Setting for PublicApi status webhook domain: ' + domainUrl,
            true,
            sessionId
        );
    }

    public static void ensureStatusWebhookRemoteSitesAsync(List<String> webhookUrls) {
        ensureStatusWebhookRemoteSitesAsync(webhookUrls, UserInfo.getSessionId());
    }

    @future(callout=true)
    public static void ensureStatusWebhookRemoteSitesAsync(List<String> webhookUrls, String sessionId) {
        if (webhookUrls == null || webhookUrls.isEmpty()) {
            return;
        }

        Set<String> processedDomains = new Set<String>();
        for (String webhookUrl : webhookUrls) {
            if (String.isBlank(webhookUrl)) {
                continue;
            }

            String domainUrl = extractDomainFromUrl(webhookUrl);
            if (String.isBlank(domainUrl) || processedDomains.contains(domainUrl)) {
                continue;
            }
            processedDomains.add(domainUrl);
            ensureStatusWebhookRemoteSite(domainUrl, sessionId);
        }
    }

    public static String createRemoteSiteSetting(
        String fullName,
        String url,
        String description,
        Boolean isActive
    ) {
        return createRemoteSiteSetting(fullName, url, description, isActive, null);
    }

    public static String createRemoteSiteSetting(
        String fullName,
        String url,
        String description,
        Boolean isActive,
        String sessionId
    ) {
        if (String.isBlank(fullName)) {
            throw new PublicApiRemoteSiteSettingException('fullName is required');
        }
        if (String.isBlank(url)) {
            throw new PublicApiRemoteSiteSettingException('url is required');
        }
        if (isActive == null) {
            isActive = true;
        }

        String endpoint = System.Url.getOrgDomainUrl().toExternalForm() + METADATA_API_ENDPOINT;
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        request.setHeader('SOAPAction', '""');
        request.setBody(buildCreateRemoteSiteSoapBody(fullName, url, description, isActive, resolveSessionId(sessionId)));

        HttpResponse response = new Http().send(request);
        String responseBody = response.getBody();

        if (response.getStatusCode() != 200) {
            throw new PublicApiRemoteSiteSettingException(
                'Metadata API callout failed with status ' + response.getStatusCode() + ': ' + responseBody
            );
        }

        if (responseBody.contains('<soapenv:Fault>') || responseBody.contains('faultcode')) {
            String faultMessage = extractFaultMessage(responseBody);
            if (isDuplicateMessage(faultMessage) || responseBody.toLowerCase().contains('duplicate')) {
                return fullName;
            }
            throw new PublicApiRemoteSiteSettingException('Metadata API returned fault: ' + faultMessage);
        }

        Boolean success = extractSuccess(responseBody);
        if (success == null || !success) {
            String errorMessage = extractErrorMessage(responseBody);
            if (isDuplicateMessage(errorMessage) || responseBody.toLowerCase().contains('duplicate')) {
                String createdFullName = extractFullName(responseBody);
                return String.isBlank(createdFullName) ? fullName : createdFullName;
            }
            throw new PublicApiRemoteSiteSettingException(
                'Failed to create Remote Site Setting' +
                (String.isNotBlank(errorMessage) ? ': ' + errorMessage : '') +
                '. Response: ' + responseBody
            );
        }

        String createdFullName = extractFullName(responseBody);
        return createdFullName != null ? createdFullName : fullName;
    }

    public static String extractDomainFromUrl(String webhookUrl) {
        if (String.isBlank(webhookUrl)) {
            return null;
        }

        try {
            URL url = new URL(webhookUrl);
            return url.getProtocol() + '://' + url.getHost();
        } catch (Exception e) {
            if (webhookUrl.startsWith('https://')) {
                Integer slashIndex = webhookUrl.indexOf('/', 8);
                return slashIndex > 0 ? webhookUrl.substring(0, slashIndex) : webhookUrl;
            }
            if (webhookUrl.startsWith('http://')) {
                Integer slashIndex = webhookUrl.indexOf('/', 7);
                return slashIndex > 0 ? webhookUrl.substring(0, slashIndex) : webhookUrl;
            }
            return webhookUrl;
        }
    }

    @TestVisible
    private static String generateRemoteSiteSettingName(String domainUrl) {
        String host = '';
        try {
            URL url = new URL(domainUrl);
            host = url.getHost();
        } catch (Exception e) {
            if (domainUrl.startsWith('https://')) {
                String temp = domainUrl.substring(8);
                Integer slashIndex = temp.indexOf('/');
                host = slashIndex > 0 ? temp.substring(0, slashIndex) : temp;
            } else if (domainUrl.startsWith('http://')) {
                String temp = domainUrl.substring(7);
                Integer slashIndex = temp.indexOf('/');
                host = slashIndex > 0 ? temp.substring(0, slashIndex) : temp;
            }
        }

        if (String.isBlank(host)) {
            host = 'Unknown';
        }

        host = host.toLowerCase();
        if (host.startsWith('www.')) {
            host = host.substring(4);
        }

        String mainDomain = host.split('\\.')[0];
        String sanitized = '';
        for (Integer i = 0; i < mainDomain.length(); i++) {
            String ch = mainDomain.substring(i, i + 1);
            if (ch >= 'a' && ch <= 'z') {
                sanitized += ch;
            } else if (sanitized.length() == 0 || sanitized.substring(sanitized.length() - 1) != '_') {
                sanitized += '_';
            }
        }

        while (sanitized.startsWith('_')) {
            sanitized = sanitized.substring(1);
        }
        while (sanitized.endsWith('_')) {
            sanitized = sanitized.substring(0, sanitized.length() - 1);
        }
        if (String.isBlank(sanitized)) {
            sanitized = 'Unknown';
        }

        String friendlyName = sanitized.substring(0, 1).toUpperCase() + sanitized.substring(1);
        String fullName = REMOTE_SITE_NAME_PREFIX + friendlyName;
        return fullName.length() > 40 ? fullName.substring(0, 40) : fullName;
    }

    private static String buildCreateRemoteSiteSoapBody(
        String fullName,
        String url,
        String description,
        Boolean isActive,
        String sessionId
    ) {
        return '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns:met="http://soap.sforce.com/2006/04/metadata" ' +
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
            '<soapenv:Header>' +
            '<met:SessionHeader>' +
            '<met:sessionId>' + escapeXml(sessionId) + '</met:sessionId>' +
            '</met:SessionHeader>' +
            '</soapenv:Header>' +
            '<soapenv:Body>' +
            '<met:createMetadata>' +
            '<met:metadata xsi:type="met:RemoteSiteSetting">' +
            '<met:fullName>' + escapeXml(fullName) + '</met:fullName>' +
            '<met:url>' + escapeXml(url) + '</met:url>' +
            '<met:description>' + escapeXml(description) + '</met:description>' +
            '<met:isActive>' + isActive + '</met:isActive>' +
            '<met:disableProtocolSecurity>false</met:disableProtocolSecurity>' +
            '</met:metadata>' +
            '</met:createMetadata>' +
            '</soapenv:Body>' +
            '</soapenv:Envelope>';
    }

    private static String resolveSessionId(String explicitSessionId) {
        String resolvedSessionId = String.isNotBlank(explicitSessionId)
            ? explicitSessionId.trim()
            : UserInfo.getSessionId();
        if (String.isBlank(resolvedSessionId)) {
            throw new PublicApiRemoteSiteSettingException(
                'Unable to create Remote Site Setting because no Salesforce session is available.'
            );
        }
        return resolvedSessionId;
    }

    private static Boolean extractSuccess(String responseBody) {
        Matcher matcher = Pattern.compile('<success>(.*?)</success>').matcher(responseBody);
        return matcher.find() ? Boolean.valueOf(matcher.group(1)) : null;
    }

    private static String extractFullName(String responseBody) {
        Matcher matcher = Pattern.compile('<fullName>(.*?)</fullName>').matcher(responseBody);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static String extractErrorMessage(String responseBody) {
        Matcher matcher = Pattern.compile('<message>(.*?)</message>').matcher(responseBody);
        List<String> errors = new List<String>();
        while (matcher.find()) {
            errors.add(matcher.group(1));
        }
        return errors.isEmpty() ? null : String.join(errors, '; ');
    }

    private static String extractFaultMessage(String responseBody) {
        Matcher matcher = Pattern.compile('<faultstring>(.*?)</faultstring>').matcher(responseBody);
        if (matcher.find()) {
            return matcher.group(1);
        }
        return responseBody.contains('<soapenv:Fault>') ? 'SOAP fault detected in response' : 'Unknown fault in response';
    }

    private static Boolean isDuplicateMessage(String message) {
        if (String.isBlank(message)) {
            return false;
        }
        String lowerMessage = message.toLowerCase();
        return lowerMessage.contains('already exists') ||
            lowerMessage.contains('duplicate') ||
            lowerMessage.contains('duplicate value');
    }

    private static String escapeXml(String input) {
        if (input == null) {
            return '';
        }
        return input.replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&apos;');
    }
}
