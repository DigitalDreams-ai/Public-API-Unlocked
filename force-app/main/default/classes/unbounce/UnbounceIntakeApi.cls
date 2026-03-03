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
            String jsonBody = req.requestBody != null ? req.requestBody.toString() : '{}';
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);

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
            if (String.isNotBlank(secret) && !UnbounceClient.verifyWebhookSignature(jsonBody, signature, secret)) {
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
