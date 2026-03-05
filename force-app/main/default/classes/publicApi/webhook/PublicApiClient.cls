/**
 * Client utilities for PublicApi webhook integration.
 * Handles signature verification for incoming PublicApi webhooks.
 */
public with sharing class PublicApiClient {

    private static final String SIGNATURE_HEADER = 'x-publicApi-signature';

    /**
     * Verifies the PublicApi webhook signature using HMAC-SHA256.
     * Returns true if signature is valid or if no secret is configured (skip verification).
     *
     * @param payload Raw request body string
     * @param signature Value from x-publicApi-signature header
     * @param secret Webhook secret from PublicApi integration config
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
            String expectedHex = generateWebhookSignature(payload, secret);
            return expectedHex != null && expectedHex.equalsIgnoreCase(signature);
        } catch (Exception e) {
            return false;
        }
    }

    public static String generateWebhookSignature(String payload, String secret) {
        if (String.isBlank(payload) || String.isBlank(secret)) {
            return null;
        }

        Blob payloadBlob = Blob.valueOf(payload);
        Blob secretBlob = Blob.valueOf(secret);
        Blob expectedMac = Crypto.generateMac('HmacSHA256', payloadBlob, secretBlob);
        return EncodingUtil.convertToHex(expectedMac);
    }
}
