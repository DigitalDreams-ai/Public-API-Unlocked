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
            String contentType = req.headers != null ? req.headers.get('Content-Type') : null;
            Map<String, Object> payload = parsePayload(requestBody, contentType);

            UnbounceConfigService.Config config;
            try {
                config = UnbounceConfigService.getConfig();
            } catch (UnbounceIntakeServiceException e) {
                res.statusCode = 503;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(e.getMessage())));
                return;
            }
            if (config == null) {
                res.statusCode = 503;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse(
                    'Unbounce integration not configured. Create an Unbounce Integration Config record with Is Active = true.'
                )));
                return;
            }

            if (String.isNotBlank(config.apiKey)) {
                String apiKeyHeader = req.headers != null ? req.headers.get('x-api-key') : null;
                if (apiKeyHeader == null || apiKeyHeader.trim() != config.apiKey.trim()) {
                    res.statusCode = 401;
                    res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('Invalid or missing API key')));
                    return;
                }
            }

            String signature = req.headers != null ? req.headers.get('x-unbounce-signature') : null;
            String secret = config.webhookSecret;
            if (String.isNotBlank(secret) && !UnbounceClient.verifyWebhookSignature(requestBody, signature, secret)) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf(JSON.serialize(new ErrorResponse('Invalid webhook signature')));
                return;
            }

            litify_pm__Intake__c intake = UnbounceIntakeService.createIntakeFromUnbounce(
                payload, config.referredByPartyName
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
