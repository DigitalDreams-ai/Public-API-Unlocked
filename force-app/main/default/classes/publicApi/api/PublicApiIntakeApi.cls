/**
 * Guest-access public API endpoint for inbound submissions.
 */
@RestResource(urlMapping='/v1/publicapi/submissions')
global with sharing class PublicApiIntakeApi {
    @HttpPost
    global static void createSubmission() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
            String apiKeyHeader = getHeaderIgnoreCase(req, 'x-api-key');
            if (String.isBlank(apiKeyHeader)) {
                writeError(res, 401, 'Invalid or missing API key');
                return;
            }

            PublicApiConfigService.Config config;
            try {
                config = PublicApiConfigService.getConfigForApiKey(apiKeyHeader);
            } catch (PublicApiIntakeServiceException e) {
                writeError(res, 503, e.getMessage());
                return;
            }
            if (config == null) {
                writeError(res, 401, 'Invalid or missing API key');
                return;
            }

            String signature = getHeaderIgnoreCase(req, 'x-publicapi-signature');
            if (String.isNotBlank(config.webhookSecret) &&
                !PublicApiClient.verifyWebhookSignature(requestBody, signature, config.webhookSecret)) {
                writeError(res, 401, 'Invalid webhook signature');
                return;
            }

            Map<String, Object> payload = parsePayload(requestBody, getHeaderIgnoreCase(req, 'Content-Type'));
            SObject submission = PublicApiIntakeService.createIntakeFromPublicApi(payload, config);
            res.statusCode = 201;
            res.responseBody = Blob.valueOf(JSON.serialize(new SubmissionResponse(submission.Id, 'Submission created successfully')));
        } catch (PublicApiIntakeServiceException e) {
            writeError(res, 400, e.getMessage());
        } catch (JSONException e) {
            writeError(res, 400, 'Invalid JSON: ' + e.getMessage());
        } catch (Exception e) {
            writeError(res, 500, e.getMessage());
        }
    }

    @TestVisible
    private static Map<String, Object> parsePayload(String requestBody, String contentType) {
        if (String.isBlank(requestBody)) {
            return new Map<String, Object>();
        }

        String normalizedContentType = contentType != null ? contentType.toLowerCase() : '';
        if (normalizedContentType.contains('application/x-www-form-urlencoded')) {
            return parseFormEncodedPayload(requestBody);
        }

        try {
            Object deserialized = JSON.deserializeUntyped(requestBody);
            if (deserialized instanceof Map<String, Object>) {
                return (Map<String, Object>) deserialized;
            }
            throw new PublicApiIntakeServiceException(
                'Invalid request body. Expected a JSON object or form-encoded key/value pairs.'
            );
        } catch (JSONException e) {
            if (looksLikeFormEncoded(requestBody)) {
                return parseFormEncodedPayload(requestBody);
            }
            throw e;
        }
    }

    private static Boolean looksLikeFormEncoded(String requestBody) {
        if (String.isBlank(requestBody)) {
            return false;
        }
        return requestBody.contains('=') &&
            !requestBody.trim().startsWith('{') &&
            !requestBody.trim().startsWith('[');
    }

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
            throw new PublicApiIntakeServiceException('Invalid form-encoded payload: ' + e.getMessage());
        }
    }

    private static String getHeaderIgnoreCase(RestRequest req, String headerName) {
        if (req == null || req.headers == null || String.isBlank(headerName)) {
            return null;
        }
        String exact = req.headers.get(headerName);
        if (exact != null) {
            return exact;
        }

        String lower = headerName.toLowerCase();
        for (String key : req.headers.keySet()) {
            if (key != null && key.toLowerCase() == lower) {
                return req.headers.get(key);
            }
        }
        return null;
    }

    private static void writeError(RestResponse res, Integer statusCode, String message) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(message)));
    }

    global class SubmissionResponse {
        public String recordId;
        public String message;
        public SubmissionResponse(String recordId, String message) {
            this.recordId = recordId;
            this.message = message;
        }
    }

    global class ErrorResponse {
        public String errorMessage;
        public ErrorResponse(String errorMessage) {
            this.errorMessage = errorMessage;
        }
    }
}
