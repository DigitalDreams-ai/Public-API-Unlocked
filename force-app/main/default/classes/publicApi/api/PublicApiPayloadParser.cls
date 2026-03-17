public without sharing class PublicApiPayloadParser {
    public static Map<String, Object> parsePayload(String requestBody, String contentType) {
        if (String.isBlank(requestBody)) {
            return new Map<String, Object>();
        }

        String normalizedContentType = contentType == null ? '' : contentType.toLowerCase();
        if (normalizedContentType.contains('multipart/form-data')) {
            return parseMultipartPayload(requestBody, contentType);
        }
        if (normalizedContentType.contains('application/x-www-form-urlencoded')) {
            return parseFormEncodedPayload(requestBody);
        }

        try {
            Object deserialized = JSON.deserializeUntyped(requestBody);
            if (deserialized instanceof Map<String, Object>) {
                return (Map<String, Object>) deserialized;
            }
            throw new PublicApiSubmissionServiceException(
                'Invalid request body. Expected a JSON object, multipart form fields, or form-encoded key/value pairs.'
            );
        } catch (JSONException e) {
            if (looksLikeFormEncoded(requestBody)) {
                return parseFormEncodedPayload(requestBody);
            }
            throw new PublicApiSubmissionServiceException('Invalid JSON: ' + e.getMessage());
        }
    }

    @TestVisible
    private static Boolean looksLikeFormEncoded(String requestBody) {
        if (String.isBlank(requestBody)) {
            return false;
        }
        return requestBody.contains('=') &&
            !requestBody.trim().startsWith('{') &&
            !requestBody.trim().startsWith('[');
    }

    @TestVisible
    private static Map<String, Object> parseMultipartPayload(String requestBody, String contentType) {
        String boundary = extractMultipartBoundary(contentType);
        if (String.isBlank(boundary)) {
            throw new PublicApiSubmissionServiceException(
                'Invalid multipart/form-data payload: missing boundary.'
            );
        }

        Map<String, Object> payload = new Map<String, Object>();
        String delimiter = '--' + boundary;
        for (String part : requestBody.split(escapeRegex(delimiter))) {
            if (String.isBlank(part)) {
                continue;
            }

            String normalizedPart = stripLeadingLineBreaks(part);
            if (normalizedPart == '--' || String.isBlank(normalizedPart.trim())) {
                continue;
            }

            Integer headerBodySplitIndex = normalizedPart.indexOf('\r\n\r\n');
            Integer separatorLength = 4;
            if (headerBodySplitIndex < 0) {
                headerBodySplitIndex = normalizedPart.indexOf('\n\n');
                separatorLength = 2;
            }
            if (headerBodySplitIndex < 0) {
                continue;
            }

            String headers = normalizedPart.substring(0, headerBodySplitIndex);
            String body = normalizedPart.substring(headerBodySplitIndex + separatorLength);
            String fieldName = extractMultipartFieldName(headers);
            if (String.isBlank(fieldName)) {
                continue;
            }

            payload.put(fieldName, stripTrailingLineBreaks(body));
        }

        return payload;
    }

    @TestVisible
    private static Map<String, Object> parseFormEncodedPayload(String requestBody) {
        Map<String, Object> payload = new Map<String, Object>();
        if (String.isBlank(requestBody)) {
            return payload;
        }

        for (String pair : requestBody.split('&')) {
            if (String.isBlank(pair)) {
                continue;
            }

            Integer equalsIndex = pair.indexOf('=');
            String encodedKey = equalsIndex >= 0 ? pair.substring(0, equalsIndex) : pair;
            String encodedValue = equalsIndex >= 0 ? pair.substring(equalsIndex + 1) : '';
            String key = urlDecodeFormValue(encodedKey);
            if (String.isBlank(key)) {
                continue;
            }
            payload.put(key, urlDecodeFormValue(encodedValue));
        }
        return payload;
    }

    private static String urlDecodeFormValue(String value) {
        if (value == null) {
            return null;
        }
        try {
            return EncodingUtil.urlDecode(value.replace('+', '%20'), 'UTF-8');
        } catch (Exception e) {
            throw new PublicApiSubmissionServiceException('Invalid form-encoded payload: ' + e.getMessage());
        }
    }

    private static String extractMultipartBoundary(String contentType) {
        if (String.isBlank(contentType)) {
            return null;
        }

        Matcher matcher = Pattern.compile('(?i)boundary="?([^";]+)"?')
            .matcher(contentType);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static String extractMultipartFieldName(String headers) {
        if (String.isBlank(headers)) {
            return null;
        }

        Matcher matcher = Pattern.compile('(?i)name="([^"]+)"')
            .matcher(headers);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static String stripLeadingLineBreaks(String value) {
        String result = value;
        while (result != null && (result.startsWith('\r\n') || result.startsWith('\n'))) {
            result = result.startsWith('\r\n') ? result.substring(2) : result.substring(1);
        }
        return result;
    }

    private static String stripTrailingLineBreaks(String value) {
        String result = value == null ? null : value;
        while (result != null && (result.endsWith('\r\n') || result.endsWith('\n'))) {
            result = result.endsWith('\r\n')
                ? result.substring(0, result.length() - 2)
                : result.substring(0, result.length() - 1);
        }
        return result;
    }

    private static String escapeRegex(String value) {
        if (value == null) {
            return null;
        }
        return value
            .replace('\\', '\\\\')
            .replace('.', '\\.')
            .replace('+', '\\+')
            .replace('*', '\\*')
            .replace('?', '\\?')
            .replace('^', '\\^')
            .replace('$', '\\$')
            .replace('(', '\\(')
            .replace(')', '\\)')
            .replace('[', '\\[')
            .replace(']', '\\]')
            .replace('{', '\\{')
            .replace('}', '\\}')
            .replace('|', '\\|');
    }
}

