public without sharing class PublicApiPayloadParser {
    public static Map<String, Object> parsePayload(String requestBody, String contentType) {
        if (String.isBlank(requestBody)) {
            return new Map<String, Object>();
        }

        String normalizedContentType = contentType == null ? '' : contentType.toLowerCase();
        if (normalizedContentType.contains('application/x-www-form-urlencoded')) {
            return parseFormEncodedPayload(requestBody);
        }

        try {
            Object deserialized = JSON.deserializeUntyped(requestBody);
            if (deserialized instanceof Map<String, Object>) {
                return (Map<String, Object>) deserialized;
            }
            throw new PublicApiSubmissionServiceException(
                'Invalid request body. Expected a JSON object or form-encoded key/value pairs.'
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
}

