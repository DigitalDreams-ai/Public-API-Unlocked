/**
 * Client utilities for Unbounce webhook integration.
 * Handles signature verification for incoming Unbounce webhooks.
 */
public with sharing class UnbounceClient {

    private static final String SIGNATURE_HEADER = 'x-unbounce-signature';

    /**
     * Verifies the Unbounce webhook signature using HMAC-SHA256.
     * Returns true if signature is valid or if no secret is configured (skip verification).
     *
     * @param payload Raw request body string
     * @param signature Value from x-unbounce-signature header
     * @param secret Webhook secret from Unbounce integration config
     * @return True if valid or verification skipped; false if signature invalid
     */
    public static Boolean verifyWebhookSignature(String payload, String signature, String secret) {
        if (String.isBlank(secret)) {
            return true;
        }
        if (String.isBlank(signature) || String.isBlank(payload)) {
            return false;
        }

        try {
            Blob payloadBlob = Blob.valueOf(payload);
            Blob secretBlob = Blob.valueOf(secret);
            Blob expectedMac = Crypto.generateMac('HmacSHA256', payloadBlob, secretBlob);
            String expectedHex = EncodingUtil.convertToHex(expectedMac);
            return expectedHex.equalsIgnoreCase(signature);
        } catch (Exception e) {
            return false;
        }
    }
}
