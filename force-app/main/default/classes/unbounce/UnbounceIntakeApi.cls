/**
 * REST API for receiving Unbounce form submission webhooks.
 * Expose via Experience Cloud: domain/apexrest/v1/unbounce/intakes
 */
@RestResource(urlMapping='/v1/unbounce/intakes')
global with sharing class UnbounceIntakeApi {

    @HttpPost
    global static void createIntake() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
            String apiKeyHeader = getHeaderIgnoreCase(req, 'x-api-key');

            if (String.isBlank(apiKeyHeader)) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('Invalid or missing API key')));
                return;
            }

            UnbounceConfigService.Config config;
            try {
                config = UnbounceConfigService.getConfigForApiKey(apiKeyHeader);
            } catch (UnbounceIntakeServiceException e) {
                res.statusCode = 503;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(e.getMessage())));
                return;
            }
            if (config == null) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('Invalid or missing API key')));
                return;
            }

            String signature = getHeaderIgnoreCase(req, 'x-unbounce-signature');
            String secret = config.webhookSecret;
            if (String.isNotBlank(secret) && !UnbounceClient.verifyWebhookSignature(requestBody, signature, secret)) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('Invalid webhook signature')));
                return;
            }

            String contentType = getHeaderIgnoreCase(req, 'Content-Type');
            Map<String, Object> payload = parsePayload(requestBody, contentType);

            litify_pm__Intake__c intake = UnbounceIntakeService.createIntakeFromUnbounce(
                payload, config
            );

            res.statusCode = 201;
            res.responseBody = Blob.valueOf(JSON.serialize(new IntakeResponse(intake.Id, 'Intake created successfully')));
        } catch (UnbounceIntakeServiceException e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(e.getMessage())));
        } catch (JSONException e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('Invalid JSON: ' + e.getMessage())));
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(e.getMessage())));
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
            throw new UnbounceIntakeServiceException(
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
        return requestBody.contains('=') && !requestBody.trim().startsWith('{') && !requestBody.trim().startsWith('[');
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
        return EncodingUtil.urlDecode(value.replace('+', '%20'), 'UTF-8');
    }

    private static String getHeaderIgnoreCase(RestRequest req, String headerName) {
        if (req == null || req.headers == null || String.isBlank(headerName)) {
            return null;
        }
        String exactValue = req.headers.get(headerName);
        if (exactValue != null) {
            return exactValue;
        }

        String lowerHeaderName = headerName.toLowerCase();
        for (String key : req.headers.keySet()) {
            if (key != null && key.toLowerCase() == lowerHeaderName) {
                return req.headers.get(key);
            }
        }
        return null;
    }

    global class IntakeResponse {
        public String intakeId;
        public String message;

        public IntakeResponse(String intakeId, String message) {
            this.intakeId = intakeId;
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
