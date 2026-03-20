import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable, getRecord, updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { wire } from 'lwc';
import ID_FIELD from '@salesforce/schema/PublicApi_Integration_Config__c.Id';
import OUTBOUND_WEBHOOK_URL_FIELD from '@salesforce/schema/PublicApi_Integration_Config__c.Outbound_Webhook_URL__c';
import getHeaderSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getHeaderSettings';

const CONFIG_FIELDS = [OUTBOUND_WEBHOOK_URL_FIELD];

export default class PublicApiRemoteSiteProvisioner extends LightningElement {
    @api recordId;

    isBusy = false;
    wiredHeaderSettingsResult;
    headerSettings;
    wiredRecordResult;
    webhookUrl = '';
    savedWebhookUrl = '';

    @wire(getRecord, { recordId: '$recordId', fields: CONFIG_FIELDS })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        if (result.data) {
            this.savedWebhookUrl = result.data.fields.Outbound_Webhook_URL__c?.value || '';
            if (!this.isBusy) {
                this.webhookUrl = this.savedWebhookUrl;
            }
        }
    }

    @wire(getHeaderSettings, { recordId: '$recordId' })
    wiredHeaderSettings(result) {
        this.wiredHeaderSettingsResult = result;
        if (result.data) {
            this.headerSettings = result.data;
        }
    }

    handleWebhookUrlChange(event) {
        this.webhookUrl = event.target.value;
    }

    async handleProvision() {
        if (!this.recordId || this.isBusy) {
            return;
        }

        this.isBusy = true;
        try {
            await this.saveWebhookUrlIfNeeded();
            const returnUrl = encodeURIComponent(window.location.pathname + window.location.search);
            window.location.assign(`/apex/PublicApiRemoteSiteProvision?id=${this.recordId}&retURL=${returnUrl}`);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Remote Site Update Failed',
                    message: this.reduceError(error),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isBusy = false;
        }
    }

    async saveWebhookUrlIfNeeded() {
        const normalizedWebhookUrl = (this.webhookUrl || '').trim();
        const normalizedSavedWebhookUrl = (this.savedWebhookUrl || '').trim();
        if (normalizedWebhookUrl === normalizedSavedWebhookUrl) {
            return;
        }

        await updateRecord({
            fields: {
                [ID_FIELD.fieldApiName]: this.recordId,
                [OUTBOUND_WEBHOOK_URL_FIELD.fieldApiName]: normalizedWebhookUrl || null
            }
        });
        this.savedWebhookUrl = normalizedWebhookUrl;
        this.webhookUrl = normalizedWebhookUrl;
    }

    get buttonLabel() {
        return this.isProvisioned ? 'Update Remote Site' : 'Provision Remote Site';
    }

    get isProvisioned() {
        return this.headerSettings?.outboundRemoteSiteStatus === 'Provisioned';
    }

    get statusLabel() {
        return this.headerSettings?.outboundRemoteSiteStatus || 'Not Provisioned';
    }

    get statusPillClass() {
        if (this.headerSettings?.outboundRemoteSiteStatus === 'Provisioned') {
            return 'status-pill status-pill_success';
        }
        if (this.headerSettings?.outboundRemoteSiteStatus === 'Failed') {
            return 'status-pill status-pill_error';
        }
        return 'status-pill status-pill_pending';
    }

    get domainLabel() {
        return this.headerSettings?.outboundRemoteSiteDomain || 'No domain cached';
    }

    get normalizedLastError() {
        return this.normalizeErrorMessage(this.headerSettings?.outboundRemoteSiteLastError);
    }

    get remoteSiteName() {
        return this.headerSettings?.outboundRemoteSiteName;
    }

    get showRemoteSiteName() {
        return !!this.remoteSiteName;
    }

    get lastError() {
        return this.normalizedLastError;
    }

    get showLastError() {
        return !!this.lastError;
    }

    get lastProvisionedLabel() {
        const value = this.headerSettings?.outboundRemoteSiteLastProvisionedAt;
        if (!value) {
            return 'Never';
        }
        try {
            return new Intl.DateTimeFormat(undefined, {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit'
            }).format(new Date(value));
        } catch (error) {
            return value;
        }
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (error.body) {
            if (typeof error.body.message === 'string' && error.body.message.length > 0) {
                return this.normalizeErrorMessage(error.body.message);
            }
            if (Array.isArray(error.body) && error.body.length > 0) {
                return this.normalizeErrorMessage(error.body
                    .map((entry) => entry && entry.message)
                    .filter((message) => !!message)
                    .join(', '));
            }
        }
        if (typeof error.message === 'string' && error.message.length > 0) {
            return this.normalizeErrorMessage(error.message);
        }
        return 'Unknown error';
    }

    normalizeErrorMessage(message) {
        if (!message) {
            return '';
        }

        const faultMatch = message.match(/<faultstring>(.*?)<\/faultstring>/i);
        if (faultMatch && faultMatch[1]) {
            return faultMatch[1].trim();
        }

        const invalidSessionMatch = message.match(/INVALID_SESSION_ID:[^<\n\r]*/i);
        if (invalidSessionMatch && invalidSessionMatch[0]) {
            return invalidSessionMatch[0].trim();
        }

        return message.trim();
    }
}
