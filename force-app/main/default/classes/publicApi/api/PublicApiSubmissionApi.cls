/**
 * Guest-access public API endpoint for inbound submissions.
 */
@RestResource(urlMapping='/v1/publicapi/*')
global with sharing class PublicApiSubmissionApi {
    @HttpPost
    global static void createSubmission() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
            String endpointPath;
            try {
                endpointPath = PublicApiEndpointPathService.extractRequestEndpointPath(req);
            } catch (PublicApiSubmissionServiceException e) {
                writeError(res, 404, e.getMessage());
                return;
            }

            PublicApiConfigService.Config config;
            try {
                config = PublicApiConfigService.getConfigForEndpointPath(endpointPath);
            } catch (PublicApiSubmissionServiceException e) {
                writeError(res, 503, e.getMessage());
                return;
            }
            if (config == null) {
                writeError(res, 404, 'No active Public API Integration Config matches the requested endpoint path.');
                return;
            }

            String apiKeyHeader = getHeaderIgnoreCase(req, 'x-api-key');
            if (String.isBlank(apiKeyHeader) || config.apiKey != apiKeyHeader.trim()) {
                writeError(res, 401, 'Invalid or missing API key');
                return;
            }

            String signature = getHeaderIgnoreCase(req, 'x-publicapi-signature');
            if (String.isNotBlank(config.webhookSecret) &&
                !PublicApiClient.verifyWebhookSignature(requestBody, signature, config.webhookSecret)) {
                writeError(res, 401, 'Invalid webhook signature');
                return;
            }

            String requestContentType = getHeaderIgnoreCase(req, 'Content-Type');
            SObject submission = PublicApiSubmissionService.createSubmissionFromPublicApi(
                requestBody,
                requestContentType,
                config
            );
            res.statusCode = 201;
            res.responseBody = Blob.valueOf(JSON.serialize(new SubmissionResponse(submission.Id, 'Submission received successfully')));
        } catch (PublicApiSubmissionServiceException e) {
            writeError(res, PublicApiSubmissionService.getHttpStatusCodeForMessage(e.getMessage()), e.getMessage());
        } catch (JSONException e) {
            writeError(res, 400, 'Invalid JSON: ' + e.getMessage());
        } catch (Exception e) {
            writeError(res, 500, e.getMessage());
        }
    }

    @TestVisible
    private static Map<String, Object> parsePayload(String requestBody, String contentType) {
        return PublicApiPayloadParser.parsePayload(requestBody, contentType);
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

