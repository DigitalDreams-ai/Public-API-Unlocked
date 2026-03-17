import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPayloadSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getPayloadSettings';
import getHeaderSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getHeaderSettings';
import getFieldReferences from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getFieldReferences';
import getLookupFieldNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getLookupFieldNames';
import getRelatedObjectApiNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getRelatedObjectApiNames';
import getLookupFieldNamesForRelatedObject from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getLookupFieldNamesForRelatedObject';
import getMatchFieldNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getMatchFieldNames';
import getCreateFieldNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getCreateFieldNames';
import getRequiredCreateFieldNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getRequiredCreateFieldNames';
import getRecordTypeDeveloperNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getRecordTypeDeveloperNames';
import getTriggerFieldNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getTriggerFieldNames';
import getTriggerFieldValues from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getTriggerFieldValues';
import savePayloadSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.savePayloadSettings';
import saveHeaderSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.saveHeaderSettings';
import provisionWebhookDomain from '@salesforce/apex/PublicApiPayloadBuilderCtrl.provisionWebhookDomain';

const DEFAULT_CONTENT_TYPE = 'application/json';
const DEFAULT_OBJECT_API_NAME = 'PublicApi_Submission__c';
const DEFAULT_ENDPOINT_PATH = '/submissions';
const SUGGESTION_LIMIT = 12;
const MAPPING_SOURCE_TYPE_INCOMING_KEY = 'IncomingKey';
const MAPPING_SOURCE_TYPE_LITERAL_VALUE = 'LiteralValue';
const INBOUND_SOURCE_TYPE_OPTIONS = [
    { label: 'Incoming Key', value: MAPPING_SOURCE_TYPE_INCOMING_KEY },
    { label: 'Literal Value', value: MAPPING_SOURCE_TYPE_LITERAL_VALUE }
];
const MULTI_MATCH_POLICY_OPTIONS = [
    { label: 'Error', value: 'Error' },
    { label: 'Use Oldest', value: 'UseOldest' },
    { label: 'Use Newest', value: 'UseNewest' }
];

let headerCounter = 0;
let mappingCounter = 0;
let relatedRuleCounter = 0;
let relatedCreateMappingCounter = 0;

export default class PublicApiJsonPayloadBuilder extends LightningElement {
    @api recordId;

    isLoading = false;
    errorMessage = '';
    isDirty = false;

    syncDirections = true;
    endpointPath = DEFAULT_ENDPOINT_PATH;
    activePayloadScope = 'inbound';
    defaultInboundRows = [];
    defaultOutboundRows = [];
    targetObjectApiName = DEFAULT_OBJECT_API_NAME;
    targetObjectSearchValue = DEFAULT_OBJECT_API_NAME;
    showObjectSuggestions = false;
    availableObjectApiNames = [];
    targetRecordTypeDeveloperName = '';
    availableTargetRecordTypeDeveloperNames = [];
    availableInboundFieldReferences = [];
    availableOutboundFieldReferences = [];
    availableRequiredInboundFieldNames = [];
    availableLookupFieldNames = [];
    outboundTriggerEnabled = true;
    outboundTriggerFieldName = '';
    outboundTriggerFieldValues = '';
    showTriggerFieldSuggestions = false;
    showTriggerValueSuggestions = false;
    availableTriggerFieldNames = [];
    availableTriggerFieldValues = [];
    inboundMappingRows = [];
    outboundMappingRows = [];
    relatedRecordRule = null;
    authMode = 'None';
    contentType = DEFAULT_CONTENT_TYPE;
    headerName = '';
    headerValue = '';
    hasWebhookSecret = false;
    outboundRemoteSiteDomain = '';
    outboundRemoteSiteName = '';
    outboundRemoteSiteStatus = '';
    outboundRemoteSiteLastError = '';
    outboundRemoteSiteLastProvisionedAt = null;
    headerRows = [];

    get authModeOptions() {
        return [
            { label: 'None', value: 'None' },
            { label: 'API Key Header', value: 'ApiKeyHeader' },
            { label: 'Bearer Token', value: 'BearerToken' },
            { label: 'Basic Auth', value: 'BasicAuth' },
            { label: 'HMAC Signature', value: 'HmacSignature' }
        ];
    }

    get multiMatchPolicyOptions() {
        return MULTI_MATCH_POLICY_OPTIONS;
    }

    get mappingSourceTypeOptions() {
        return INBOUND_SOURCE_TYPE_OPTIONS;
    }

    get targetRecordTypeOptions() {
        return [
            { label: 'Use default behavior', value: '' },
            ...(this.availableTargetRecordTypeDeveloperNames || []).map((value) => ({
                label: value,
                value
            }))
        ];
    }

    get valuePlaceholder() {
        return `$${this.targetObjectApiName || DEFAULT_OBJECT_API_NAME}.Status__c`;
    }

    get payloadHelpText() {
        return this.syncDirections
            ? 'Inbound and outbound mappings stay in sync for shared key-to-field rows. Inbound-only literal and default rows stay on the inbound side.'
            : 'Inbound and outbound mappings are independent. Edit each tab separately.';
    }

    get hasInboundMappingRows() {
        return this.inboundMappingRows.length > 0;
    }

    get hasOutboundMappingRows() {
        return this.outboundMappingRows.length > 0;
    }

    get hasRelatedRecordRows() {
        return this.relatedRecordRule !== null;
    }

    get endpointUrlPreview() {
        const origin = typeof window !== 'undefined' && window.location ? window.location.origin : '';
        return `${origin}/services/apexrest/v1/publicapi${this.endpointPath || DEFAULT_ENDPOINT_PATH}`;
    }

    get activeRelatedRecordRow() {
        return this.relatedRecordRule;
    }

    get mappingPreviewJson() {
        return JSON.stringify(this.buildPayloadPreview(), null, 2);
    }

    get relatedRecordsPreviewJson() {
        return JSON.stringify(this.buildRelatedRuleConfig(this.activeRelatedRecordRow), null, 2);
    }

    get triggersPreviewJson() {
        return JSON.stringify(
            {
                enabled: this.outboundTriggerEnabled,
                fieldName: this.outboundTriggerFieldName || null,
                values: this.parseTriggerValues(this.outboundTriggerFieldValues)
            },
            null,
            2
        );
    }

    get filteredTriggerFieldSuggestions() {
        const normalizedSearch = (this.outboundTriggerFieldName || '').trim().toLowerCase();
        return this.availableTriggerFieldNames
            .filter((value) => !normalizedSearch || value.toLowerCase().includes(normalizedSearch))
            .slice(0, SUGGESTION_LIMIT)
            .map((value) => ({ label: value, value }));
    }

    get hasTriggerFieldSuggestions() {
        return this.filteredTriggerFieldSuggestions.length > 0;
    }

    get filteredTriggerValueSuggestions() {
        const normalizedSearch = this.getCurrentTriggerValueToken().toLowerCase();
        return this.availableTriggerFieldValues
            .filter((value) => !normalizedSearch || value.toLowerCase().includes(normalizedSearch))
            .slice(0, SUGGESTION_LIMIT)
            .map((value) => ({ label: value, value }));
    }

    get hasTriggerValueSuggestions() {
        return this.filteredTriggerValueSuggestions.length > 0;
    }

    get payloadPreviewTitle() {
        return this.activePayloadScope === 'outbound' ? 'Outbound Payload Preview' : 'Inbound Payload Preview';
    }

    get hasHeaderRows() {
        return this.headerRows.length > 0;
    }

    get headersPreviewJson() {
        return JSON.stringify(this.buildEffectiveHeadersObject(), null, 2);
    }

    get remoteSiteStatusLabel() {
        return this.outboundRemoteSiteStatus || 'Not Provisioned';
    }

    get remoteSiteStatusVariant() {
        if (this.outboundRemoteSiteStatus === 'Provisioned') {
            return 'success';
        }
        if (this.outboundRemoteSiteStatus === 'Failed') {
            return 'error';
        }
        return 'offline';
    }

    get isSaveDisabled() {
        return this.isLoading || !this.isDirty;
    }

    get isNoAuthMode() {
        return this.authMode === 'None';
    }

    get isHmacMode() {
        return this.authMode === 'HmacSignature';
    }

    get isBearerMode() {
        return this.authMode === 'BearerToken';
    }

    get isBasicMode() {
        return this.authMode === 'BasicAuth';
    }

    get isApiKeyMode() {
        return this.authMode === 'ApiKeyHeader';
    }

    get showPrimaryHeaderSection() {
        return !this.isNoAuthMode;
    }

    get showPrimaryHeaderValueInput() {
        return !this.isNoAuthMode && !this.isHmacMode;
    }

    get primaryHeaderSectionTitle() {
        if (this.isApiKeyMode) {
            return 'Primary API Key Header';
        }
        if (this.isBearerMode) {
            return 'Primary Bearer Header';
        }
        if (this.isBasicMode) {
            return 'Primary Basic Auth Header';
        }
        if (this.isHmacMode) {
            return 'Primary Signature Header';
        }
        return 'Primary Header';
    }

    get primaryHeaderSectionBody() {
        if (this.isNoAuthMode) {
            return 'No auth header will be added. Use Additional Headers only for non-auth custom headers.';
        }
        if (this.isApiKeyMode) {
            return 'This header carries the API key for the receiving system.';
        }
        if (this.isBearerMode) {
            return 'This header sends Bearer <token>. Leave the name blank to default to Authorization.';
        }
        if (this.isBasicMode) {
            return 'This header sends Basic <base64(username:password)>. Leave the name blank to default to Authorization.';
        }
        if (this.isHmacMode) {
            return 'This header carries the generated request signature. The signature value comes from the Outbound Webhook Secret.';
        }
        return '';
    }

    get authSummaryLabel() {
        if (this.authMode === 'ApiKeyHeader') {
            return `${this.headerName || 'X-API-KEY'}: ${this.headerValue || '[missing value]'}`;
        }
        if (this.authMode === 'BearerToken') {
            return `${this.headerName || 'Authorization'}: Bearer ${this.headerValue || '[missing token]'}`;
        }
        if (this.authMode === 'BasicAuth') {
            return `${this.headerName || 'Authorization'}: Basic [base64 encoded at send time]`;
        }
        if (this.authMode === 'HmacSignature') {
            return `${this.headerName || 'x-publicapi-signature'}: ${this.hasWebhookSecret ? '[generated at send time]' : '[missing webhook secret]'}`;
        }
        return 'No auth header configured';
    }

    get filteredObjectSuggestions() {
        const normalizedSearch = (this.targetObjectSearchValue || '').trim().toLowerCase();
        return this.availableObjectApiNames
            .filter((value) => !normalizedSearch || value.toLowerCase().includes(normalizedSearch))
            .slice(0, SUGGESTION_LIMIT)
            .map((value) => ({ label: value, value }));
    }

    get hasObjectSuggestions() {
        return this.filteredObjectSuggestions.length > 0;
    }

    get inboundSourceKeyOptions() {
        const seen = new Set();
        const options = [];
        (this.inboundMappingRows || []).forEach((row) => {
            const externalKey = (row?.externalKey || '').trim();
            if (!externalKey) {
                return;
            }
            const normalizedKey = externalKey.toLowerCase();
            if (seen.has(normalizedKey)) {
                return;
            }
            seen.add(normalizedKey);
            options.push(externalKey);
        });
        options.sort();
        return options;
    }

    connectedCallback() {
        this.loadConfiguration();
    }

    async loadConfiguration() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const [payloadSettings, headerSettings] = await Promise.all([
                getPayloadSettings({ recordId: this.recordId }),
                getHeaderSettings({ recordId: this.recordId })
            ]);

            this.syncDirections = payloadSettings?.syncInboundAndOutbound !== false;
            this.endpointPath = payloadSettings?.endpointPath || DEFAULT_ENDPOINT_PATH;
            this.targetObjectApiName = payloadSettings?.targetObjectApiName || DEFAULT_OBJECT_API_NAME;
            this.targetObjectSearchValue = this.targetObjectApiName;
            this.availableObjectApiNames = payloadSettings?.availableObjectApiNames || [];
            this.targetRecordTypeDeveloperName = payloadSettings?.targetRecordTypeDeveloperName || '';
            this.availableTargetRecordTypeDeveloperNames =
                payloadSettings?.availableTargetRecordTypeDeveloperNames || [];
            this.availableInboundFieldReferences = payloadSettings?.availableInboundFieldReferences || [];
            this.availableOutboundFieldReferences = payloadSettings?.availableOutboundFieldReferences || [];
            this.availableRequiredInboundFieldNames =
                payloadSettings?.availableRequiredInboundFieldNames || [];
            this.availableLookupFieldNames = payloadSettings?.availableLookupFieldNames || [];
            this.outboundTriggerEnabled = payloadSettings?.outboundTriggerEnabled !== false;
            this.outboundTriggerFieldName = payloadSettings?.outboundTriggerFieldName || '';
            this.outboundTriggerFieldValues = payloadSettings?.outboundTriggerFieldValues || '';
            this.availableTriggerFieldNames = payloadSettings?.availableTriggerFieldNames || [];
            this.availableTriggerFieldValues = payloadSettings?.availableTriggerFieldValues || [];
            this.defaultInboundRows = this.parseMappingArray(
                'inbound',
                payloadSettings?.defaultInboundJson
            );
            this.defaultOutboundRows = this.parseMappingArray(
                'outbound',
                payloadSettings?.defaultOutboundJson
            );

            this.inboundMappingRows = this.ensureRequiredInboundMappings(
                this.parseMappingArray(
                    'inbound',
                    payloadSettings?.inboundConfigurationJson || payloadSettings?.defaultInboundJson
                ),
                this.availableRequiredInboundFieldNames
            );
            this.outboundMappingRows = this.parseMappingArray(
                'outbound',
                payloadSettings?.outboundConfigurationJson || payloadSettings?.defaultOutboundJson
            );
            if (this.syncDirections) {
                this.outboundMappingRows = this.cloneRows(this.inboundMappingRows, 'outbound');
            }
            this.relatedRecordRule = this.parseRelatedRuleConfig(
                payloadSettings?.relatedRecordConfigurationJson
            );
            if (!this.relatedRecordRule) {
                this.relatedRecordRule = this.createRelatedRuleRow();
            }
            await this.refreshRelatedRuleMetadata();

            this.authMode = headerSettings?.authMode || 'None';
            this.contentType = headerSettings?.contentType || DEFAULT_CONTENT_TYPE;
            this.headerName = headerSettings?.headerName || '';
            this.headerValue = headerSettings?.headerValue || '';
            this.hasWebhookSecret = !!headerSettings?.hasWebhookSecret;
            this.outboundRemoteSiteDomain = headerSettings?.outboundRemoteSiteDomain || '';
            this.outboundRemoteSiteName = headerSettings?.outboundRemoteSiteName || '';
            this.outboundRemoteSiteStatus = headerSettings?.outboundRemoteSiteStatus || '';
            this.outboundRemoteSiteLastError = headerSettings?.outboundRemoteSiteLastError || '';
            this.outboundRemoteSiteLastProvisionedAt =
                headerSettings?.outboundRemoteSiteLastProvisionedAt || null;
            this.headerRows = this.parseHeaderConfiguration(headerSettings?.additionalHeadersJson);
            this.isDirty = false;
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleSave() {
        if (!this.validateBeforeSave()) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        try {
            await Promise.all([
                savePayloadSettings({
                    recordId: this.recordId,
                    syncInboundAndOutbound: this.syncDirections,
                    endpointPath: this.endpointPath,
                    targetObjectApiName: this.targetObjectApiName,
                    targetRecordTypeDeveloperName: this.targetRecordTypeDeveloperName,
                    relatedRecordConfigurationJson: JSON.stringify(
                        this.buildRelatedRuleConfig(this.activeRelatedRecordRow),
                        null,
                        2
                    ),
                    outboundTriggerEnabled: this.outboundTriggerEnabled,
                    outboundTriggerFieldName: this.outboundTriggerFieldName,
                    outboundTriggerFieldValues: this.outboundTriggerFieldValues,
                    inboundConfigJson: JSON.stringify(this.buildMappingArray(this.inboundMappingRows), null, 2),
                    outboundConfigJson: JSON.stringify(this.buildMappingArray(this.outboundMappingRows), null, 2)
                }),
                saveHeaderSettings({
                    recordId: this.recordId,
                    authMode: this.authMode,
                    contentType: this.contentType,
                    headerName: this.headerName,
                    headerValue: this.headerValue,
                    additionalHeadersJson: JSON.stringify(this.buildHeadersObject(), null, 2)
                })
            ]);

            this.isDirty = false;
            this.clearSuggestionState();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Request builder configuration saved.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    handleSyncDirectionsChange(event) {
        this.syncDirections = event.target.checked;
        if (this.syncDirections) {
            this.outboundMappingRows = this.cloneRows(this.inboundMappingRows, 'outbound');
        }
        this.isDirty = true;
    }

    handleTargetRecordTypeChange(event) {
        this.targetRecordTypeDeveloperName = event.detail.value || '';
        this.isDirty = true;
    }

    handleEndpointPathChange(event) {
        this.endpointPath = event.target.value || DEFAULT_ENDPOINT_PATH;
        this.isDirty = true;
    }

    handleTargetObjectInput(event) {
        this.targetObjectSearchValue = event.target.value || '';
        this.showObjectSuggestions = true;
    }

    handleTargetObjectFocus() {
        this.showObjectSuggestions = true;
    }

    handleTargetObjectBlur() {
        window.setTimeout(async () => {
            this.showObjectSuggestions = false;
            const matchedValue = this.resolveTargetObjectValue(this.targetObjectSearchValue);
            if (matchedValue) {
                await this.applyTargetObjectSelection(matchedValue);
                return;
            }
            this.targetObjectSearchValue = this.targetObjectApiName;
        }, 150);
    }

    async handleSelectTargetObject(event) {
        const value = event.currentTarget.dataset.value;
        if (!value) {
            return;
        }
        await this.applyTargetObjectSelection(value);
    }

    handleOutboundTriggerEnabledChange(event) {
        this.outboundTriggerEnabled = event.target.checked;
        this.isDirty = true;
    }

    handleTriggerFieldInput(event) {
        this.outboundTriggerFieldName = event.target.value || '';
        this.showTriggerFieldSuggestions = true;
        this.isDirty = true;
        this.refreshTriggerFieldValuesForCurrentField();
    }

    handleTriggerFieldFocus() {
        this.showTriggerFieldSuggestions = true;
    }

    handleTriggerFieldBlur() {
        window.setTimeout(() => {
            this.showTriggerFieldSuggestions = false;
        }, 150);
    }

    async handleSelectTriggerFieldSuggestion(event) {
        const value = event.currentTarget.dataset.value;
        if (!value) {
            return;
        }
        this.outboundTriggerFieldName = value;
        this.showTriggerFieldSuggestions = false;
        this.isDirty = true;
        await this.refreshTriggerFieldValues();
    }

    handleTriggerValuesInput(event) {
        this.outboundTriggerFieldValues = event.target.value || '';
        this.showTriggerValueSuggestions = true;
        this.isDirty = true;
    }

    handleTriggerValuesFocus() {
        this.showTriggerValueSuggestions = true;
    }

    handleTriggerValuesBlur() {
        window.setTimeout(() => {
            this.showTriggerValueSuggestions = false;
        }, 150);
    }

    handleSelectTriggerValueSuggestion(event) {
        const value = event.currentTarget.dataset.value;
        if (!value) {
            return;
        }
        this.outboundTriggerFieldValues = this.mergeTriggerValue(value);
        this.showTriggerValueSuggestions = false;
        this.isDirty = true;
    }

    handlePayloadTabActive(event) {
        this.activePayloadScope = event.target.value || 'inbound';
    }

    handleLoadDefaultMappings() {
        this.inboundMappingRows = this.ensureRequiredInboundMappings(
            this.cloneRows(this.defaultInboundRows, 'inbound'),
            this.availableRequiredInboundFieldNames
        );
        this.outboundMappingRows = this.syncDirections
            ? this.cloneRows(this.inboundMappingRows, 'outbound')
            : this.cloneRows(this.defaultOutboundRows, 'outbound');
        this.relatedRecordRule = this.rehydrateRelatedRule(this.relatedRecordRule);
        this.errorMessage = '';
        this.isDirty = true;
    }

    handleClearInboundMappings() {
        this.inboundMappingRows = this.ensureRequiredInboundMappings(
            [],
            this.availableRequiredInboundFieldNames
        );
        if (this.syncDirections) {
            this.outboundMappingRows = this.cloneRows(this.inboundMappingRows, 'outbound');
        }
        this.relatedRecordRule = this.rehydrateRelatedRule(this.relatedRecordRule);
        this.errorMessage = '';
        this.isDirty = true;
    }

    handleClearOutboundMappings() {
        this.setRowsForScope('outbound', []);
        this.errorMessage = '';
    }

    handleAddInboundMappingRow() {
        this.setRowsForScope('inbound', [...this.inboundMappingRows, this.createMappingRow('inbound')]);
    }

    handleAddOutboundMappingRow() {
        this.setRowsForScope('outbound', [...this.outboundMappingRows, this.createMappingRow('outbound')]);
    }

    handleMappingExternalKeyChange(event) {
        this.updateMappingRow(event.target.dataset.scope, event.target.dataset.id, {
            externalKey: event.target.value || ''
        });
    }

    handleMappingSourceTypeChange(event) {
        const sourceType = this.normalizeMappingSourceType(event.detail.value);
        this.updateMappingRow(event.target.dataset.scope, event.target.dataset.id, {
            sourceType,
            showSuggestions: false,
            suggestions: sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE ? [] : undefined
        });
    }

    handleMappingLiteralValueChange(event) {
        this.updateMappingRow(event.target.dataset.scope, event.target.dataset.id, {
            literalValue: event.target.value || ''
        });
    }

    handleMappingDefaultValueChange(event) {
        this.updateMappingRow(event.target.dataset.scope, event.target.dataset.id, {
            defaultValue: event.target.value || ''
        });
    }

    handleMappingValueInput(event) {
        const scope = event.target.dataset.scope;
        this.updateMappingRow(scope, event.target.dataset.id, {
            value: event.target.value || '',
            showSuggestions: true,
            suggestions: this.getFilteredFieldSuggestions(scope, event.target.value || '')
        });
    }

    handleMappingValueFocus(event) {
        const scope = event.target.dataset.scope;
        const row = this.findMappingRow(scope, event.target.dataset.id);
        if (!row) {
            return;
        }
        this.updateMappingRow(scope, row.id, {
            showSuggestions: true,
            suggestions: this.getFilteredFieldSuggestions(scope, row.value)
        });
    }

    handleMappingValueBlur(event) {
        const scope = event.target.dataset.scope;
        const rowId = event.target.dataset.id;
        window.setTimeout(() => {
            this.updateMappingRow(scope, rowId, { showSuggestions: false });
        }, 150);
    }

    handleSelectMappingSuggestion(event) {
        const scope = event.currentTarget.dataset.scope;
        const rowId = event.currentTarget.dataset.rowId;
        const value = event.currentTarget.dataset.value;
        this.updateMappingRow(scope, rowId, {
            value,
            showSuggestions: false,
            suggestions: this.getFilteredFieldSuggestions(scope, value)
        });
    }

    handleRemoveMapping(event) {
        this.removeMappingRow(event.currentTarget.dataset.scope, event.currentTarget.dataset.id);
    }

    handleResetRelatedRule() {
        this.relatedRecordRule = this.createRelatedRuleRow();
        this.isDirty = true;
    }

    async handleRelatedLookupFieldInput(event) {
        const rowId = event.target.dataset.id;
        const typedValue = event.target.value || '';
        const row = this.findRelatedRuleRow(rowId);
        this.updateRelatedRuleRow(rowId, {
            targetLookupField: typedValue,
            showLookupFieldSuggestions: true
        });

        const matchedValue = this.resolveExactMatch(row?.availableLookupFieldNames || [], typedValue);
        if (matchedValue && row) {
            const needsRefresh = row.targetLookupField !== matchedValue;
            if (needsRefresh) {
                await this.applyRelatedLookupFieldSelection(rowId, matchedValue);
            }
        }
    }

    handleRelatedLookupFieldFocus(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, { showLookupFieldSuggestions: true });
    }

    handleRelatedLookupFieldBlur(event) {
        const rowId = event.target.dataset.id;
        window.setTimeout(async () => {
            const row = this.findRelatedRuleRow(rowId);
            if (!row) {
                return;
            }

            const matchedValue = this.resolveExactMatch(
                row.availableLookupFieldNames || [],
                row.targetLookupField
            );
            if (matchedValue) {
                await this.applyRelatedLookupFieldSelection(rowId, matchedValue);
                return;
            }

            this.updateRelatedRuleRow(rowId, {
                targetLookupField: row.targetLookupField || '',
                showLookupFieldSuggestions: false
            });
        }, 150);
    }

    async handleSelectRelatedLookupFieldSuggestion(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const value = event.currentTarget.dataset.value;
        await this.applyRelatedLookupFieldSelection(rowId, value);
        this.isDirty = true;
    }

    async applyRelatedLookupFieldSelection(rowId, value) {
        const row = this.findRelatedRuleRow(rowId);
        if (!row) {
            return;
        }

        const selectedValue = (value || '').trim();
        const changed = row.targetLookupField !== selectedValue;
        this.updateRelatedRuleRow(rowId, {
            targetLookupField: selectedValue,
            showLookupFieldSuggestions: false
        });
        this.isDirty = this.isDirty || changed;
    }

    async handleRelatedObjectInput(event) {
        const rowId = event.target.dataset.id;
        const typedValue = event.target.value || '';
        this.updateRelatedRuleRow(rowId, {
            relatedObjectSearchValue: typedValue,
            showRelatedObjectSuggestions: true
        });

        const row = this.findRelatedRuleRow(rowId);
        const matchedValue = this.resolveExactMatch(row?.availableRelatedObjectApiNames || [], typedValue);
        if (matchedValue && row && row.relatedObjectApiName !== matchedValue) {
            await this.applyRelatedObjectSelection(rowId, matchedValue);
        }
    }

    handleRelatedObjectFocus(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, { showRelatedObjectSuggestions: true });
    }

    handleRelatedObjectBlur(event) {
        const rowId = event.target.dataset.id;
        window.setTimeout(async () => {
            const row = this.findRelatedRuleRow(rowId);
            if (!row) {
                return;
            }

            const matchedValue = this.resolveExactMatch(
                row.availableRelatedObjectApiNames || [],
                row.relatedObjectSearchValue
            );
            if (matchedValue) {
                await this.applyRelatedObjectSelection(rowId, matchedValue);
                return;
            }

            this.updateRelatedRuleRow(rowId, {
                relatedObjectSearchValue: row.relatedObjectApiName || '',
                showRelatedObjectSuggestions: false
            });
        }, 150);
    }

    async handleSelectRelatedObjectSuggestion(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const value = event.currentTarget.dataset.value;
        await this.applyRelatedObjectSelection(rowId, value);
    }

    handleRelatedMatchFieldInput(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, {
            matchFieldName: event.target.value || '',
            showMatchFieldSuggestions: true
        });
    }

    handleRelatedMatchFieldFocus(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, { showMatchFieldSuggestions: true });
    }

    handleRelatedMatchFieldBlur(event) {
        const rowId = event.target.dataset.id;
        window.setTimeout(() => {
            this.updateRelatedRuleRow(rowId, { showMatchFieldSuggestions: false });
        }, 150);
    }

    handleSelectRelatedMatchFieldSuggestion(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const value = event.currentTarget.dataset.value;
        this.updateRelatedRuleRow(rowId, {
            matchFieldName: value,
            showMatchFieldSuggestions: false
        });
        this.isDirty = true;
    }

    handleRelatedSourceKeyChange(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, {
            sourceKey: event.target.value || '',
            showSourceKeySuggestions: true
        });
    }

    handleRelatedSourceKeyFocus(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, {
            showSourceKeySuggestions: true
        });
    }

    handleRelatedSourceKeyBlur(event) {
        const rowId = event.target.dataset.id;
        window.setTimeout(() => {
            this.updateRelatedRuleRow(rowId, { showSourceKeySuggestions: false });
        }, 150);
    }

    handleSelectRelatedSourceKeySuggestion(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const value = event.currentTarget.dataset.value;
        this.updateRelatedRuleRow(rowId, {
            sourceKey: value,
            showSourceKeySuggestions: false
        });
    }

    async handleRelatedCreateIfMissingChange(event) {
        const rowId = event.target.dataset.id;
        const createIfMissing = event.target.checked;
        this.updateRelatedRuleRow(rowId, { createIfMissing });
        if (createIfMissing) {
            await this.refreshRelatedRuleMetadata(rowId);
        }
    }

    handleRelatedCreateRecordTypeChange(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, {
            createRecordTypeDeveloperName: event.detail.value || ''
        });
    }

    handleRelatedMultiMatchPolicyChange(event) {
        this.updateRelatedRuleRow(event.target.dataset.id, {
            onMultipleMatches: event.detail.value
        });
    }

    handleAddRelatedCreateMapping(event) {
        const rowId = event.currentTarget.dataset.id;
        const row = this.findRelatedRuleRow(rowId);
        if (!row) {
            return;
        }
        this.updateRelatedRuleRow(rowId, {
            createMappings: [...row.createMappings, this.createRelatedCreateMappingRow()]
        });
    }

    handleRemoveRelatedCreateMapping(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const mappingId = event.currentTarget.dataset.id;
        const row = this.findRelatedRuleRow(rowId);
        if (!row) {
            return;
        }
        this.updateRelatedRuleRow(rowId, {
            createMappings: row.createMappings.filter((mapping) => mapping.id !== mappingId)
        });
    }

    handleRelatedCreateSourceKeyChange(event) {
        this.updateRelatedCreateMapping(event.target.dataset.rowId, event.target.dataset.id, {
            sourceKey: event.target.value || '',
            showSourceKeySuggestions: true
        });
    }

    handleRelatedCreateSourceKeyFocus(event) {
        this.updateRelatedCreateMapping(event.target.dataset.rowId, event.target.dataset.id, {
            showSourceKeySuggestions: true
        });
    }

    handleRelatedCreateSourceKeyBlur(event) {
        const rowId = event.target.dataset.rowId;
        const mappingId = event.target.dataset.id;
        window.setTimeout(() => {
            this.updateRelatedCreateMapping(rowId, mappingId, { showSourceKeySuggestions: false });
        }, 150);
    }

    handleSelectRelatedCreateSourceKeySuggestion(event) {
        this.updateRelatedCreateMapping(
            event.currentTarget.dataset.rowId,
            event.currentTarget.dataset.mappingId,
            {
                sourceKey: event.currentTarget.dataset.value,
                showSourceKeySuggestions: false
            }
        );
    }

    handleRelatedCreateFieldInput(event) {
        this.updateRelatedCreateMapping(event.target.dataset.rowId, event.target.dataset.id, {
            fieldName: event.target.value || '',
            showFieldSuggestions: true
        });
    }

    handleRelatedCreateFieldFocus(event) {
        this.updateRelatedCreateMapping(event.target.dataset.rowId, event.target.dataset.id, {
            showFieldSuggestions: true
        });
    }

    handleRelatedCreateFieldBlur(event) {
        const rowId = event.target.dataset.rowId;
        const mappingId = event.target.dataset.id;
        window.setTimeout(() => {
            this.updateRelatedCreateMapping(rowId, mappingId, { showFieldSuggestions: false });
        }, 150);
    }

    handleSelectRelatedCreateFieldSuggestion(event) {
        this.updateRelatedCreateMapping(
            event.currentTarget.dataset.rowId,
            event.currentTarget.dataset.mappingId,
            {
                fieldName: event.currentTarget.dataset.value,
                showFieldSuggestions: false
            }
        );
    }

    createMappingRow(
        scope,
        externalKey = '',
        value = '',
        sortOrder = 0,
        sourceType = MAPPING_SOURCE_TYPE_INCOMING_KEY,
        literalValue = '',
        defaultValue = ''
    ) {
        mappingCounter++;
        return this.hydrateMappingRow({
            id: `mapping_${mappingCounter}`,
            externalKey,
            value,
            scope: scope || 'inbound',
            sortOrder,
            sourceType,
            literalValue,
            defaultValue,
            showSuggestions: false
        });
    }

    hydrateMappingRow(row) {
        const scope = row?.scope || 'inbound';
        const sourceType = this.normalizeMappingSourceType(row?.sourceType);
        const suggestions = this.getFilteredFieldSuggestions(scope, row.value);
        return {
            ...row,
            scope,
            sourceType,
            literalValue: row?.literalValue || '',
            defaultValue: row?.defaultValue || '',
            isIncomingKeySourceType: sourceType === MAPPING_SOURCE_TYPE_INCOMING_KEY,
            isLiteralSourceType: sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE,
            showDefaultValueInput:
                scope === 'inbound' && sourceType === MAPPING_SOURCE_TYPE_INCOMING_KEY,
            sourceFieldLabel:
                sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE ? 'Literal Value' : 'Incoming Key',
            suggestions,
            hasSuggestions: suggestions.length > 0
        };
    }

    parseMappingArray(scope, configJson) {
        if (!configJson) {
            return [];
        }

        let parsed;
        try {
            parsed = JSON.parse(configJson);
        } catch (error) {
            return [];
        }
        if (!Array.isArray(parsed)) {
            return [];
        }

        return parsed.map((row) =>
            this.createMappingRow(
                scope,
                row.externalKey || '',
                row.value || '',
                Number.isFinite(Number(row.sortOrder)) ? Number(row.sortOrder) : 0,
                row.sourceType || MAPPING_SOURCE_TYPE_INCOMING_KEY,
                row.literalValue || '',
                row.defaultValue || ''
            )
        );
    }

    buildPayloadPreview() {
        const rows = this.activePayloadScope === 'outbound' ? this.outboundMappingRows : this.inboundMappingRows;
        const preview = {};
        this.buildMappingArray(rows).forEach((row, index) => {
            preview[this.getPreviewKey(row, index)] = this.getPreviewValueForRow(row);
        });
        return preview;
    }

    getPreviewKey(row, index) {
        if (this.activePayloadScope === 'inbound' &&
            this.normalizeMappingSourceType(row?.sourceType) === MAPPING_SOURCE_TYPE_LITERAL_VALUE) {
            const fieldApiName = this.getFieldReferenceFieldApiName(row?.value);
            return `[literal] ${fieldApiName || `row_${index + 1}`}`;
        }
        return row?.externalKey || `[row_${index + 1}]`;
    }

    getPreviewValueForRow(row) {
        if (this.activePayloadScope === 'inbound' &&
            this.normalizeMappingSourceType(row?.sourceType) === MAPPING_SOURCE_TYPE_LITERAL_VALUE) {
            return row?.literalValue || '';
        }
        return this.getPreviewValue(row?.value);
    }

    getPreviewValue(fieldReference) {
        const normalizedReference = String(fieldReference || '').trim();
        if (!normalizedReference.startsWith('$')) {
            return null;
        }

        const fieldApiName = normalizedReference.substring(normalizedReference.indexOf('.') + 1).toLowerCase();
        const previewValues = {
            'received_at__c': '2026-03-03T05:38:21.000Z',
            'createddate': '2026-03-03T05:38:21.000Z',
            'status__c': 'Converted',
            'name': 'Acme Public API'
        };
        return Object.prototype.hasOwnProperty.call(previewValues, fieldApiName)
            ? previewValues[fieldApiName]
            : null;
    }

    buildMappingArray(rows) {
        return rows
            .map((row, index) => ({
                externalKey: (row.externalKey || '').trim(),
                value: (row.value || '').trim(),
                sortOrder: index + 1,
                scope: row?.scope || 'inbound',
                sourceType: this.normalizeMappingSourceType(row?.sourceType),
                literalValue: (row?.literalValue || '').trim(),
                defaultValue: (row?.defaultValue || '').trim()
            }))
            .filter((row) => {
                if (row.scope === 'outbound') {
                    return row.externalKey && row.value;
                }
                if (row.sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE) {
                    return row.value;
                }
                return row.externalKey && row.value;
            })
            .map((row) => {
                const serialized = {
                    value: row.value,
                    sortOrder: row.sortOrder
                };
                if (row.scope === 'outbound') {
                    serialized.externalKey = row.externalKey;
                    return serialized;
                }
                serialized.sourceType = row.sourceType;
                if (row.sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE) {
                    serialized.literalValue = row.literalValue;
                } else {
                    serialized.externalKey = row.externalKey;
                    if ((row.defaultValue || '') !== '') {
                        serialized.defaultValue = row.defaultValue;
                    }
                }
                return serialized;
            });
    }

    updateMappingRow(scope, rowId, changes) {
        const updatedRows = this.getRowsForScope(scope).map((row) => {
            if (row.id !== rowId) {
                return row;
            }
            return this.hydrateMappingRow({
                ...row,
                ...changes
            });
        });
        this.setRowsForScope(scope, updatedRows);
    }

    removeMappingRow(scope, rowId) {
        const updatedRows = this.getRowsForScope(scope).filter((row) => row.id !== rowId);
        this.setRowsForScope(scope, updatedRows);
    }

    setRowsForScope(scope, rows) {
        const normalizedRows = this.rehydrateRowsForScope(scope, rows);
        if (scope === 'outbound') {
            this.outboundMappingRows = normalizedRows;
            if (this.syncDirections) {
                this.inboundMappingRows = this.ensureRequiredInboundMappings(
                    this.cloneRows(normalizedRows, 'inbound'),
                    this.availableRequiredInboundFieldNames
                );
            }
        } else {
            this.inboundMappingRows = normalizedRows;
            if (this.syncDirections) {
                this.outboundMappingRows = this.cloneRows(normalizedRows, 'outbound');
            }
        }
        this.relatedRecordRule = this.rehydrateRelatedRule(this.relatedRecordRule);
        this.isDirty = true;
    }

    getRowsForScope(scope) {
        return scope === 'outbound' ? this.outboundMappingRows : this.inboundMappingRows;
    }

    normalizeMappingSourceType(sourceType) {
        return sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE
            ? MAPPING_SOURCE_TYPE_LITERAL_VALUE
            : MAPPING_SOURCE_TYPE_INCOMING_KEY;
    }

    getFieldReferenceFieldApiName(fieldReference) {
        const normalizedReference = String(fieldReference || '').trim();
        if (!normalizedReference.startsWith('$') || normalizedReference.indexOf('.') < 0) {
            return '';
        }
        return normalizedReference.substring(normalizedReference.indexOf('.') + 1).trim();
    }

    findMappingRow(scope, rowId) {
        return this.getRowsForScope(scope).find((row) => row.id === rowId);
    }

    cloneRows(rows, targetScope) {
        return rows
            .map((row) => {
                const effectiveScope = targetScope || row.scope;
                const sourceType = this.normalizeMappingSourceType(row?.sourceType);
                if (effectiveScope === 'outbound' && sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE) {
                    return null;
                }
                return this.createMappingRow(
                    effectiveScope,
                    row.externalKey,
                    row.value,
                    row.sortOrder,
                    effectiveScope === 'outbound' ? MAPPING_SOURCE_TYPE_INCOMING_KEY : sourceType,
                    effectiveScope === 'outbound' ? '' : row.literalValue,
                    effectiveScope === 'outbound' ? '' : row.defaultValue
                );
            })
            .filter((row) => row !== null);
    }

    rehydrateRowsForScope(scope, rows) {
        const hydratedRows = (rows || []).map((row) =>
            this.hydrateMappingRow({
                ...row,
                scope
            })
        );
        return scope === 'inbound'
            ? this.ensureRequiredInboundMappings(hydratedRows, this.availableRequiredInboundFieldNames)
            : hydratedRows;
    }

    getFieldReferenceOptions(scope) {
        return scope === 'outbound' ? this.availableOutboundFieldReferences : this.availableInboundFieldReferences;
    }

    resolveTargetObjectValue(value) {
        const normalizedValue = (value || '').trim();
        if (!normalizedValue) {
            return '';
        }

        const matchedValue = this.availableObjectApiNames.find(
            (option) => option.toLowerCase() === normalizedValue.toLowerCase()
        );
        return matchedValue || '';
    }

    resolveExactMatch(values, value) {
        const normalizedValue = (value || '').trim();
        if (!normalizedValue) {
            return '';
        }

        const matchedValue = (values || []).find(
            (option) => option && option.toLowerCase() === normalizedValue.toLowerCase()
        );
        return matchedValue || '';
    }

    getFilteredFieldSuggestions(scope, searchTerm) {
        const normalizedSearchTerm = (searchTerm || '').trim().toLowerCase();
        return this.getFieldReferenceOptions(scope)
            .filter((reference) => !normalizedSearchTerm || reference.toLowerCase().includes(normalizedSearchTerm))
            .slice(0, SUGGESTION_LIMIT)
            .map((reference) => ({
                label: reference,
                value: reference
            }));
    }

    isValidFieldReference(scope, value) {
        const normalizedValue = (value || '').trim();
        return !normalizedValue || this.getFieldReferenceOptions(scope).includes(normalizedValue);
    }

    createRelatedRuleRow(rule = {}) {
        relatedRuleCounter++;
        return this.hydrateRelatedRuleRow({
            id: rule.id || `related_${relatedRuleCounter}`,
            targetLookupField: rule.targetLookupField || '',
            relatedObjectApiName: rule.relatedObjectApiName || '',
            relatedObjectSearchValue: rule.relatedObjectApiName || '',
            matchFieldName: rule.matchFieldName || '',
            sourceKey: rule.sourceKey || '',
            createIfMissing: rule.createIfMissing === true,
            createRecordTypeDeveloperName: rule.createRecordTypeDeveloperName || '',
            onMultipleMatches: rule.onMultipleMatches || 'Error',
            createMappings: (rule.createMappings || []).map((mapping) => this.createRelatedCreateMappingRow(mapping)),
            availableLookupFieldNames: rule.availableLookupFieldNames || [],
            availableRelatedObjectApiNames: rule.availableRelatedObjectApiNames || [],
            availableMatchFieldNames: rule.availableMatchFieldNames || [],
            availableCreateFieldNames: rule.availableCreateFieldNames || [],
            availableRequiredCreateFieldNames: rule.availableRequiredCreateFieldNames || [],
            availableCreateRecordTypeDeveloperNames: rule.availableCreateRecordTypeDeveloperNames || [],
            showLookupFieldSuggestions: false,
            showRelatedObjectSuggestions: false,
            showMatchFieldSuggestions: false,
            showSourceKeySuggestions: false
        });
    }

    createRelatedCreateMappingRow(mapping = {}) {
        relatedCreateMappingCounter++;
        return {
            id: mapping.id || `related_create_${relatedCreateMappingCounter}`,
            sourceKey: mapping.sourceKey || '',
            fieldName: mapping.fieldName || '',
            showFieldSuggestions: false,
            showSourceKeySuggestions: false
        };
    }

    hydrateRelatedRuleRow(row) {
        const lookupFieldSuggestions = this.getFilteredSuggestions(
            row.availableLookupFieldNames || [],
            row.targetLookupField
        );
        const relatedObjectSuggestions = this.getFilteredSuggestions(
            row.availableRelatedObjectApiNames || [],
            row.relatedObjectSearchValue
        );
        const matchFieldSuggestions = this.getFilteredSuggestions(
            row.availableMatchFieldNames || [],
            row.matchFieldName
        );
        const sourceKeySuggestions = this.getFilteredSuggestions(
            this.inboundSourceKeyOptions,
            row.sourceKey
        );

        return {
            ...row,
            lookupFieldSuggestions,
            hasLookupFieldSuggestions: lookupFieldSuggestions.length > 0,
            relatedObjectSuggestions,
            hasRelatedObjectSuggestions: relatedObjectSuggestions.length > 0,
            matchFieldSuggestions,
            hasMatchFieldSuggestions: matchFieldSuggestions.length > 0,
            sourceKeySuggestions,
            hasSourceKeySuggestions: sourceKeySuggestions.length > 0,
            createRecordTypeOptions: [
                { label: 'Use default behavior', value: '' },
                ...((row.availableCreateRecordTypeDeveloperNames || []).map((value) => ({
                    label: value,
                    value
                })))
            ],
            createMappings: (row.createMappings || []).map((mapping) =>
                this.hydrateRelatedCreateMappingRow(mapping, row.availableCreateFieldNames || [])
            ),
            hasCreateMappings: (row.createMappings || []).length > 0
        };
    }

    hydrateRelatedCreateMappingRow(mapping, availableCreateFieldNames) {
        const fieldSuggestions = this.getFilteredSuggestions(
            availableCreateFieldNames || [],
            mapping.fieldName
        );
        const sourceKeySuggestions = this.getFilteredSuggestions(
            this.inboundSourceKeyOptions,
            mapping.sourceKey
        );
        return {
            ...mapping,
            fieldSuggestions,
            hasFieldSuggestions: fieldSuggestions.length > 0,
            sourceKeySuggestions,
            hasSourceKeySuggestions: sourceKeySuggestions.length > 0
        };
    }

    parseRelatedRuleConfig(configJson) {
        if (!configJson) {
            return null;
        }

        let parsed;
        try {
            parsed = JSON.parse(configJson);
        } catch (error) {
            return null;
        }
        if (Array.isArray(parsed)) {
            return null;
        }

        if (!parsed || typeof parsed !== 'object') {
            return null;
        }

        return this.createRelatedRuleRow(parsed);
    }

    buildRelatedRuleConfig(row) {
        if (!row) {
            return null;
        }

        const rule = {
            targetLookupField: (row.targetLookupField || '').trim(),
            relatedObjectApiName: (row.relatedObjectApiName || '').trim(),
            matchFieldName: (row.matchFieldName || '').trim(),
            sourceKey: (row.sourceKey || '').trim(),
            createIfMissing: row.createIfMissing === true,
            createRecordTypeDeveloperName: (row.createRecordTypeDeveloperName || '').trim(),
            onMultipleMatches: row.onMultipleMatches || 'Error',
            createMappings: (row.createMappings || [])
                .map((mapping) => ({
                    sourceKey: (mapping.sourceKey || '').trim(),
                    fieldName: (mapping.fieldName || '').trim()
                }))
                .filter((mapping) => mapping.sourceKey || mapping.fieldName)
        };

        const hasContent =
            rule.targetLookupField ||
            rule.relatedObjectApiName ||
            rule.matchFieldName ||
            rule.sourceKey ||
            rule.createRecordTypeDeveloperName ||
            rule.createMappings.length > 0;
        return hasContent ? rule : null;
    }

    updateRelatedRuleRow(rowId, changes) {
        if (!this.relatedRecordRule || this.relatedRecordRule.id !== rowId) {
            return;
        }
        this.relatedRecordRule = this.hydrateRelatedRuleRow({
            ...this.relatedRecordRule,
            ...changes
        });
        this.isDirty = true;
    }

    updateRelatedCreateMapping(rowId, mappingId, changes) {
        if (!this.relatedRecordRule || this.relatedRecordRule.id !== rowId) {
            return;
        }
        this.relatedRecordRule = this.hydrateRelatedRuleRow({
            ...this.relatedRecordRule,
            createMappings: this.relatedRecordRule.createMappings.map((mapping) =>
                mapping.id === mappingId ? { ...mapping, ...changes } : mapping
            )
        });
        this.isDirty = true;
    }

    findRelatedRuleRow(rowId) {
        if (!this.relatedRecordRule) {
            return null;
        }
        return this.relatedRecordRule.id === rowId ? this.relatedRecordRule : null;
    }

    rehydrateRelatedRule(row) {
        return row ? this.hydrateRelatedRuleRow(row) : null;
    }

    async applyTargetObjectSelection(value) {
        const selectedValue = (value || '').trim();
        if (!selectedValue) {
            return;
        }

        const changed = this.targetObjectApiName !== selectedValue;
        this.showObjectSuggestions = false;
        this.targetObjectApiName = selectedValue;
        this.targetObjectSearchValue = selectedValue;
        await this.refreshMetadataForTargetObject();
        if (!this.availableTargetRecordTypeDeveloperNames.includes(this.targetRecordTypeDeveloperName)) {
            this.targetRecordTypeDeveloperName = '';
        }
        this.inboundMappingRows = this.rehydrateRowsForScope('inbound', this.inboundMappingRows);
        this.outboundMappingRows = this.syncDirections
            ? this.cloneRows(this.inboundMappingRows, 'outbound')
            : this.rehydrateRowsForScope('outbound', this.outboundMappingRows);
        this.relatedRecordRule = this.rehydrateRelatedRule(this.relatedRecordRule);
        await this.refreshRelatedRuleMetadata();
        this.isDirty = this.isDirty || changed;
    }

    async applyRelatedObjectSelection(rowId, value) {
        const row = this.findRelatedRuleRow(rowId);
        if (!row) {
            return;
        }

        const selectedValue = (value || '').trim();
        const changed = row.relatedObjectApiName !== selectedValue;
        if (changed) {
            this.updateRelatedRuleRow(rowId, {
                relatedObjectApiName: selectedValue,
                relatedObjectSearchValue: selectedValue,
                targetLookupField: '',
                matchFieldName: '',
                createMappings: [],
                createRecordTypeDeveloperName: '',
                showRelatedObjectSuggestions: false
            });
        } else {
            this.updateRelatedRuleRow(rowId, {
                relatedObjectSearchValue: selectedValue,
                showRelatedObjectSuggestions: false
            });
        }
        await this.refreshRelatedRuleMetadata(rowId);
        this.isDirty = this.isDirty || changed;
    }

    async refreshRelatedRuleMetadata(rowId) {
        const effectiveRowId = rowId || this.relatedRecordRule?.id;
        const row = this.findRelatedRuleRow(effectiveRowId);
        if (!row) {
            return;
        }

        let availableLookupFieldNames = [];
        let availableRelatedObjectApiNames = await this.fetchRelatedObjectApiNames(
            this.targetObjectApiName
        );
        let availableMatchFieldNames = [];
        let availableCreateFieldNames = [];
        let availableRequiredCreateFieldNames = [];
        let availableCreateRecordTypeDeveloperNames = [];

        const relatedObjectApiName = availableRelatedObjectApiNames.includes(row.relatedObjectApiName)
            ? row.relatedObjectApiName
            : '';
        if (relatedObjectApiName) {
            [
                availableLookupFieldNames,
                availableMatchFieldNames,
                availableCreateFieldNames,
                availableRequiredCreateFieldNames,
                availableCreateRecordTypeDeveloperNames
            ] = await Promise.all([
                this.fetchLookupFieldNamesForRelatedObject(this.targetObjectApiName, relatedObjectApiName),
                this.fetchMatchFieldNames(relatedObjectApiName),
                this.fetchCreateFieldNames(relatedObjectApiName),
                this.fetchRequiredCreateFieldNames(relatedObjectApiName),
                this.fetchRecordTypeDeveloperNames(relatedObjectApiName)
            ]);
        }

        const normalizedMappings = (row.createMappings || []).map((mapping) => ({
            ...mapping,
            fieldName: availableCreateFieldNames.includes(mapping.fieldName) ? mapping.fieldName : ''
        }));
        const hydratedMappings = row.createIfMissing
            ? this.ensureRequiredCreateMappings(
                normalizedMappings,
                availableRequiredCreateFieldNames
            )
            : normalizedMappings;

        this.relatedRecordRule = this.hydrateRelatedRuleRow({
            ...row,
            relatedObjectApiName,
            relatedObjectSearchValue: relatedObjectApiName || row.relatedObjectSearchValue,
            targetLookupField: availableLookupFieldNames.includes(row.targetLookupField)
                ? row.targetLookupField
                : '',
            matchFieldName: availableMatchFieldNames.includes(row.matchFieldName)
                ? row.matchFieldName
                : '',
            createRecordTypeDeveloperName: availableCreateRecordTypeDeveloperNames.includes(
                row.createRecordTypeDeveloperName
            )
                ? row.createRecordTypeDeveloperName
                : '',
            createMappings: hydratedMappings,
            availableLookupFieldNames,
            availableRelatedObjectApiNames,
            availableMatchFieldNames,
            availableCreateFieldNames,
            availableRequiredCreateFieldNames,
            availableCreateRecordTypeDeveloperNames
        });
    }

    getFilteredSuggestions(values, searchTerm) {
        const normalizedSearch = (searchTerm || '').trim().toLowerCase();
        return (values || [])
            .filter((value) => !normalizedSearch || value.toLowerCase().includes(normalizedSearch))
            .slice(0, SUGGESTION_LIMIT)
            .map((value) => ({ label: value, value }));
    }

    ensureRequiredCreateMappings(existingMappings, requiredFieldNames) {
        const hydratedMappings = [...(existingMappings || [])];
        const existingFieldNames = new Set(
            hydratedMappings
                .map((mapping) => (mapping.fieldName || '').trim().toLowerCase())
                .filter((value) => value)
        );

        (requiredFieldNames || []).forEach((fieldName) => {
            const normalizedFieldName = (fieldName || '').trim().toLowerCase();
            if (!normalizedFieldName || existingFieldNames.has(normalizedFieldName)) {
                return;
            }
            hydratedMappings.push(
                this.createRelatedCreateMappingRow({
                    fieldName,
                    sourceKey: ''
                })
            );
            existingFieldNames.add(normalizedFieldName);
        });

        return hydratedMappings;
    }

    ensureRequiredInboundMappings(existingMappings, requiredFieldNames) {
        const hydratedMappings = [...(existingMappings || [])];
        const existingFieldNames = new Set(
            hydratedMappings
                .map((mapping) => this.getFieldReferenceFieldApiName(mapping?.value))
                .map((value) => (value || '').trim().toLowerCase())
                .filter((value) => value)
        );

        (requiredFieldNames || []).forEach((fieldName) => {
            const normalizedFieldName = (fieldName || '').trim().toLowerCase();
            if (!normalizedFieldName || existingFieldNames.has(normalizedFieldName)) {
                return;
            }
            hydratedMappings.push(
                this.createMappingRow(
                    'inbound',
                    '',
                    `$${this.targetObjectApiName || DEFAULT_OBJECT_API_NAME}.${fieldName}`,
                    hydratedMappings.length + 1,
                    MAPPING_SOURCE_TYPE_LITERAL_VALUE,
                    '',
                    ''
                )
            );
            existingFieldNames.add(normalizedFieldName);
        });

        return hydratedMappings;
    }

    mappingRowHasContent(scope, row) {
        const normalizedScope = scope || row?.scope || 'inbound';
        if (normalizedScope === 'outbound') {
            return !!((row?.externalKey || '').trim() || (row?.value || '').trim());
        }

        const sourceType = this.normalizeMappingSourceType(row?.sourceType);
        if (sourceType === MAPPING_SOURCE_TYPE_LITERAL_VALUE) {
            return !!((row?.literalValue || '').trim() || (row?.value || '').trim());
        }
        return !!(
            (row?.externalKey || '').trim() ||
            (row?.defaultValue || '').trim() ||
            (row?.value || '').trim()
        );
    }

    clearSuggestionState() {
        this.inboundMappingRows = this.inboundMappingRows.map((row) =>
            this.hydrateMappingRow({ ...row, showSuggestions: false })
        );
        this.outboundMappingRows = this.outboundMappingRows.map((row) =>
            this.hydrateMappingRow({ ...row, showSuggestions: false })
        );
        this.relatedRecordRule = this.relatedRecordRule
            ? this.hydrateRelatedRuleRow({
                ...this.relatedRecordRule,
                showLookupFieldSuggestions: false,
                showRelatedObjectSuggestions: false,
                showMatchFieldSuggestions: false,
                showSourceKeySuggestions: false,
                createMappings: this.relatedRecordRule.createMappings.map((mapping) => ({
                    ...mapping,
                    showFieldSuggestions: false,
                    showSourceKeySuggestions: false
                }))
            })
            : null;
        this.showTriggerFieldSuggestions = false;
        this.showTriggerValueSuggestions = false;
    }

    validateBeforeSave() {
        let isValid = true;
        this.errorMessage = '';

        if (!this.availableObjectApiNames.includes(this.targetObjectApiName)) {
            this.errorMessage = 'Select a valid target object before saving.';
            return false;
        }

        const targetRecordTypeInput = this.template.querySelector(
            'lightning-combobox[data-role="target-record-type"]'
        );
        if (targetRecordTypeInput) {
            let message = '';
            if ((this.targetRecordTypeDeveloperName || '').trim() &&
                !this.availableTargetRecordTypeDeveloperNames.includes(
                    (this.targetRecordTypeDeveloperName || '').trim()
                )) {
                message = 'Select a valid target record type.';
            }
            targetRecordTypeInput.setCustomValidity(message);
            targetRecordTypeInput.reportValidity();
            isValid = isValid && !message;
        }

        const triggerFieldInput = this.template.querySelector('lightning-input[data-role="trigger-field-name"]');
        const triggerValuesInput = this.template.querySelector('lightning-input[data-role="trigger-field-values"]');
        if (triggerFieldInput) {
            let message = '';
            if ((this.outboundTriggerFieldName || '').trim() &&
                !this.availableTriggerFieldNames.includes((this.outboundTriggerFieldName || '').trim())) {
                message = 'Select a valid outbound trigger field name.';
            }
            triggerFieldInput.setCustomValidity(message);
            triggerFieldInput.reportValidity();
            isValid = isValid && !message;
        }

        if (triggerValuesInput) {
            let message = '';
            if ((this.outboundTriggerFieldValues || '').trim() &&
                this.availableTriggerFieldValues.length > 0 &&
                !this.areValidTriggerValues()) {
                message = 'Select valid outbound trigger values from the suggested list.';
            }
            triggerValuesInput.setCustomValidity(message);
            triggerValuesInput.reportValidity();
            isValid = isValid && !message;
        }

        const rowsByScope = {
            inbound: new Map(this.inboundMappingRows.map((row) => [row.id, row])),
            outbound: new Map(this.outboundMappingRows.map((row) => [row.id, row]))
        };
        const validateScopes = ['inbound'];
        if (!this.syncDirections) {
            validateScopes.push('outbound');
        }

        const externalKeyInputs = this.template.querySelectorAll('lightning-input[data-role="mapping-external-key"]');
        const literalValueInputs = this.template.querySelectorAll('lightning-input[data-role="mapping-literal-value"]');
        const valueInputs = this.template.querySelectorAll('lightning-input[data-role="mapping-value"]');

        externalKeyInputs.forEach((input) => {
            const scope = input.dataset.scope;
            if (!validateScopes.includes(scope)) {
                input.setCustomValidity('');
                input.reportValidity();
                return;
            }
            const row = rowsByScope[scope].get(input.dataset.id);
            const hasAnyValue = this.mappingRowHasContent(scope, row);
            const message = hasAnyValue && !(row?.externalKey || '').trim() ? 'External key is required.' : '';
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        literalValueInputs.forEach((input) => {
            const scope = input.dataset.scope;
            if (!validateScopes.includes(scope)) {
                input.setCustomValidity('');
                input.reportValidity();
                return;
            }
            const row = rowsByScope[scope].get(input.dataset.id);
            const hasAnyValue = this.mappingRowHasContent(scope, row);
            const message = hasAnyValue && !(row?.literalValue || '').trim()
                ? 'Literal value is required.'
                : '';
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        valueInputs.forEach((input) => {
            const scope = input.dataset.scope;
            if (!validateScopes.includes(scope)) {
                input.setCustomValidity('');
                input.reportValidity();
                return;
            }
            const row = rowsByScope[scope].get(input.dataset.id);
            const hasAnyValue = this.mappingRowHasContent(scope, row);
            let message = '';
            if (hasAnyValue && !(row?.value || '').trim()) {
                message = 'Value is required.';
            } else if ((row?.value || '').trim() && !this.isValidFieldReference(scope, row.value)) {
                message = `Enter a valid object field reference, for example ${this.valuePlaceholder}.`;
            }
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        const relatedRow = this.relatedRecordRule;
        const relatedLookupInputs = this.template.querySelectorAll('lightning-input[data-role="related-lookup-field"]');
        const relatedObjectInputs = this.template.querySelectorAll('lightning-input[data-role="related-object"]');
        const relatedMatchInputs = this.template.querySelectorAll('lightning-input[data-role="related-match-field"]');
        const relatedSourceInputs = this.template.querySelectorAll('lightning-input[data-role="related-source-key"]');
        const relatedCreateFieldInputs = this.template.querySelectorAll('lightning-input[data-role="related-create-field"]');
        const relatedCreateSourceInputs = this.template.querySelectorAll('lightning-input[data-role="related-create-source-key"]');
        const relatedCreateRecordTypeInputs =
            this.template.querySelectorAll('lightning-combobox[data-role="related-create-record-type"]');

        relatedLookupInputs.forEach((input) => {
            const hasAnyValue = this.relatedRowHasContent(relatedRow);
            let message = '';
            if (hasAnyValue && !(relatedRow?.targetLookupField || '').trim()) {
                message = 'Lookup field is required.';
            } else if ((relatedRow?.targetLookupField || '').trim() &&
                !(relatedRow?.availableLookupFieldNames || []).includes((relatedRow.targetLookupField || '').trim())) {
                message = 'Select a valid lookup field on the target object.';
            }
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        relatedObjectInputs.forEach((input) => {
            const hasAnyValue = this.relatedRowHasContent(relatedRow);
            let message = '';
            if (hasAnyValue && !(relatedRow?.relatedObjectApiName || '').trim()) {
                message = 'Related object is required.';
            } else if ((relatedRow?.relatedObjectApiName || '').trim() &&
                !(relatedRow?.availableRelatedObjectApiNames || []).includes((relatedRow.relatedObjectApiName || '').trim())) {
                message = 'Select a valid related object.';
            }
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        relatedMatchInputs.forEach((input) => {
            const hasAnyValue = this.relatedRowHasContent(relatedRow);
            let message = '';
            if (hasAnyValue && !(relatedRow?.matchFieldName || '').trim()) {
                message = 'Match field is required.';
            } else if ((relatedRow?.matchFieldName || '').trim() &&
                !(relatedRow?.availableMatchFieldNames || []).includes((relatedRow.matchFieldName || '').trim())) {
                message = 'Select a valid related match field.';
            }
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        relatedSourceInputs.forEach((input) => {
            const hasAnyValue = this.relatedRowHasContent(relatedRow);
            const message = hasAnyValue && !(relatedRow?.sourceKey || '').trim() ? 'Source key is required.' : '';
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        relatedCreateRecordTypeInputs.forEach((input) => {
            let message = '';
            if ((relatedRow?.createRecordTypeDeveloperName || '').trim() &&
                !((relatedRow?.availableCreateRecordTypeDeveloperNames || []).includes(
                    (relatedRow.createRecordTypeDeveloperName || '').trim()
                ))) {
                message = 'Select a valid create record type.';
            }
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        relatedCreateFieldInputs.forEach((input) => {
            const mapping = (relatedRow?.createMappings || []).find((candidate) => candidate.id === input.dataset.id);
            const hasAnyValue = !!((mapping?.sourceKey || '').trim() || (mapping?.fieldName || '').trim());
            let message = '';
            if (hasAnyValue && !(mapping?.fieldName || '').trim()) {
                message = 'Field name is required.';
            } else if ((mapping?.fieldName || '').trim() &&
                !(relatedRow?.availableCreateFieldNames || []).includes((mapping.fieldName || '').trim())) {
                message = 'Select a valid create field.';
            }
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        relatedCreateSourceInputs.forEach((input) => {
            const mapping = (relatedRow?.createMappings || []).find((candidate) => candidate.id === input.dataset.id);
            const hasAnyValue = !!((mapping?.sourceKey || '').trim() || (mapping?.fieldName || '').trim());
            const message = hasAnyValue && !(mapping?.sourceKey || '').trim() ? 'Source key is required.' : '';
            input.setCustomValidity(message);
            input.reportValidity();
            isValid = isValid && !message;
        });

        if (!isValid) {
            this.errorMessage = 'Fix the request builder configuration before saving.';
        }
        return isValid;
    }

    relatedRowHasContent(row) {
        if (!row) {
            return false;
        }
        return !!(
            (row.targetLookupField || '').trim() ||
            (row.relatedObjectApiName || '').trim() ||
            (row.matchFieldName || '').trim() ||
            (row.sourceKey || '').trim() ||
            (row.createRecordTypeDeveloperName || '').trim() ||
            (row.createMappings || []).some((mapping) =>
                (mapping.sourceKey || '').trim() || (mapping.fieldName || '').trim()
            )
        );
    }

    handleAddHeaderRow() {
        this.headerRows = [...this.headerRows, this.createHeaderRow()];
        this.isDirty = true;
    }

    handleAuthModeChange(event) {
        this.authMode = event.detail.value;
        this.isDirty = true;
    }

    handleContentTypeChange(event) {
        this.contentType = event.target.value || '';
        this.isDirty = true;
    }

    handlePrimaryHeaderNameChange(event) {
        this.headerName = event.target.value || '';
        this.isDirty = true;
    }

    handlePrimaryHeaderValueChange(event) {
        this.headerValue = event.target.value || '';
        this.isDirty = true;
    }

    handleClearHeaders() {
        this.headerRows = [];
        this.isDirty = true;
    }

    async handleProvisionWebhookDomain() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const headerSettings = await provisionWebhookDomain({ recordId: this.recordId });
            this.headerName = headerSettings?.headerName || '';
            this.headerValue = headerSettings?.headerValue || '';
            this.hasWebhookSecret = !!headerSettings?.hasWebhookSecret;
            this.outboundRemoteSiteDomain = headerSettings?.outboundRemoteSiteDomain || '';
            this.outboundRemoteSiteName = headerSettings?.outboundRemoteSiteName || '';
            this.outboundRemoteSiteStatus = headerSettings?.outboundRemoteSiteStatus || '';
            this.outboundRemoteSiteLastError = headerSettings?.outboundRemoteSiteLastError || '';
            this.outboundRemoteSiteLastProvisionedAt =
                headerSettings?.outboundRemoteSiteLastProvisionedAt || null;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Webhook domain provisioning completed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    handleHeaderNameChange(event) {
        this.updateHeaderRow(event.target.dataset.id, 'name', event.target.value || '');
    }

    handleHeaderValueChange(event) {
        this.updateHeaderRow(event.target.dataset.id, 'value', event.target.value || '');
    }

    handleRemoveHeader(event) {
        const rowId = event.currentTarget.dataset.id;
        this.headerRows = this.headerRows.filter((row) => row.id !== rowId);
        this.isDirty = true;
    }

    createHeaderRow(name = '', value = '') {
        headerCounter++;
        return {
            id: `header_${headerCounter}`,
            name,
            value
        };
    }

    parseHeaderConfiguration(configJson) {
        if (!configJson) {
            return [];
        }

        let parsed;
        try {
            parsed = JSON.parse(configJson);
        } catch (error) {
            return [];
        }
        if (Array.isArray(parsed)) {
            return parsed
                .map((row) => this.createHeaderRow(row.name || row.header || '', row.value || ''))
                .filter((row) => !this.isManagedHeaderName(row.name));
        }
        if (parsed && typeof parsed === 'object') {
            return Object.keys(parsed)
                .filter((key) => !this.isManagedHeaderName(key))
                .map((key) => this.createHeaderRow(key, parsed[key] == null ? '' : String(parsed[key])));
        }
        return [];
    }

    buildHeadersObject() {
        const result = {};
        this.headerRows.forEach((row) => {
            const name = (row.name || '').trim();
            if (!name) {
                return;
            }
            result[name] = row.value || '';
        });
        return result;
    }

    buildEffectiveHeadersObject() {
        const result = {
            'Content-Type': this.contentType || DEFAULT_CONTENT_TYPE,
            'X-PublicApi-Event-Type': 'status_changed'
        };

        if (this.authMode === 'ApiKeyHeader' && this.headerValue) {
            result[this.headerName || 'X-API-KEY'] = this.headerValue;
        } else if (this.authMode === 'BearerToken' && this.headerValue) {
            result[this.headerName || 'Authorization'] = `Bearer ${this.headerValue}`;
        } else if (this.authMode === 'BasicAuth' && this.headerValue) {
            result[this.headerName || 'Authorization'] = 'Basic [base64 encoded at send time]';
        } else if (this.authMode === 'HmacSignature') {
            result[this.headerName || 'x-publicapi-signature'] =
                this.hasWebhookSecret ? '[generated at send time]' : '[missing webhook secret]';
        }

        return {
            ...result,
            ...this.buildHeadersObject()
        };
    }

    isManagedHeaderName(headerName) {
        const normalizedName = (headerName || '').trim().toLowerCase();
        if (!normalizedName) {
            return false;
        }

        const managedHeaderNames = new Set(['content-type', 'x-publicapi-event-type']);

        if (this.authMode === 'ApiKeyHeader') {
            managedHeaderNames.add((this.headerName || 'X-API-KEY').trim().toLowerCase());
        } else if (this.authMode === 'BearerToken' || this.authMode === 'BasicAuth') {
            managedHeaderNames.add((this.headerName || 'Authorization').trim().toLowerCase());
        } else if (this.authMode === 'HmacSignature') {
            managedHeaderNames.add((this.headerName || 'x-publicapi-signature').trim().toLowerCase());
        }

        return managedHeaderNames.has(normalizedName);
    }

    updateHeaderRow(rowId, field, value) {
        this.headerRows = this.headerRows.map((row) =>
            row.id === rowId ? { ...row, [field]: value } : row
        );
        this.isDirty = true;
    }

    extractErrorMessage(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return JSON.stringify(error);
    }

    async refreshFieldReferences() {
        this.availableInboundFieldReferences = await this.fetchFieldReferences(this.targetObjectApiName, true);
        this.availableOutboundFieldReferences = await this.fetchFieldReferences(this.targetObjectApiName, false);
    }

    async refreshMetadataForTargetObject() {
        await Promise.all([
            this.refreshTargetRecordTypeDeveloperNames(),
            this.refreshFieldReferences(),
            this.refreshRequiredInboundFieldNames(),
            this.refreshLookupFieldNames(),
            this.refreshTriggerFieldNames()
        ]);
        await this.refreshTriggerFieldValues();
    }

    async fetchFieldReferences(objectApiName, inboundMode) {
        try {
            return await getFieldReferences({
                objectApiName,
                inboundMode
            });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            return [];
        }
    }

    async refreshLookupFieldNames() {
        try {
            this.availableLookupFieldNames = await getLookupFieldNames({
                objectApiName: this.targetObjectApiName
            });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.availableLookupFieldNames = [];
        }
    }

    async fetchRelatedObjectApiNames(objectApiName) {
        try {
            return await getRelatedObjectApiNames({
                objectApiName
            });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            return [];
        }
    }

    async fetchLookupFieldNamesForRelatedObject(objectApiName, relatedObjectApiName) {
        try {
            return await getLookupFieldNamesForRelatedObject({
                objectApiName,
                relatedObjectApiName
            });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            return [];
        }
    }

    async fetchMatchFieldNames(objectApiName) {
        try {
            return await getMatchFieldNames({ objectApiName });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            return [];
        }
    }

    async fetchCreateFieldNames(objectApiName) {
        try {
            return await getCreateFieldNames({ objectApiName });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            return [];
        }
    }

    async fetchRequiredCreateFieldNames(objectApiName) {
        try {
            return await getRequiredCreateFieldNames({ objectApiName });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            return [];
        }
    }

    async fetchRecordTypeDeveloperNames(objectApiName) {
        try {
            return await getRecordTypeDeveloperNames({ objectApiName });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            return [];
        }
    }

    async refreshTargetRecordTypeDeveloperNames() {
        this.availableTargetRecordTypeDeveloperNames = await this.fetchRecordTypeDeveloperNames(
            this.targetObjectApiName
        );
    }

    async refreshRequiredInboundFieldNames() {
        this.availableRequiredInboundFieldNames = await this.fetchRequiredCreateFieldNames(
            this.targetObjectApiName
        );
    }

    async refreshTriggerFieldNames() {
        try {
            this.availableTriggerFieldNames = await getTriggerFieldNames({
                objectApiName: DEFAULT_OBJECT_API_NAME
            });
            if (!this.availableTriggerFieldNames.includes((this.outboundTriggerFieldName || '').trim())) {
                this.outboundTriggerFieldName = '';
                this.outboundTriggerFieldValues = '';
            }
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.availableTriggerFieldNames = [];
        }
    }

    async refreshTriggerFieldValues() {
        const normalizedFieldName = (this.outboundTriggerFieldName || '').trim();
        if (!normalizedFieldName) {
            this.availableTriggerFieldValues = [];
            return;
        }

        try {
            this.availableTriggerFieldValues = await getTriggerFieldValues({
                objectApiName: DEFAULT_OBJECT_API_NAME,
                fieldName: normalizedFieldName
            });
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.availableTriggerFieldValues = [];
        }
    }

    refreshTriggerFieldValuesForCurrentField() {
        const normalizedFieldName = (this.outboundTriggerFieldName || '').trim();
        if (this.availableTriggerFieldNames.includes(normalizedFieldName)) {
            this.refreshTriggerFieldValues();
        } else {
            this.availableTriggerFieldValues = [];
        }
    }

    getCurrentTriggerValueToken() {
        const rawValue = this.outboundTriggerFieldValues || '';
        const normalized = rawValue.replace(/\r/g, '\n').replace(/;/g, ',');
        const segments = normalized.split(/[,\n]+/);
        return (segments.pop() || '').trim();
    }

    mergeTriggerValue(selectedValue) {
        const rawValue = this.outboundTriggerFieldValues || '';
        const normalized = rawValue.replace(/\r/g, '\n').replace(/;/g, ',');
        const endsWithDelimiter = /[,\n]\s*$/.test(normalized);
        let tokens = normalized
            .split(/[,\n]+/)
            .map((token) => token.trim())
            .filter((token) => token);

        if (endsWithDelimiter || tokens.length === 0) {
            if (!tokens.includes(selectedValue)) {
                tokens.push(selectedValue);
            }
            return tokens.join(', ');
        }

        tokens[tokens.length - 1] = selectedValue;
        return Array.from(new Set(tokens)).join(', ');
    }

    parseTriggerValues(rawValues) {
        return (rawValues || '')
            .replace(/\r/g, '\n')
            .replace(/;/g, ',')
            .split(/[,\n]+/)
            .map((value) => value.trim())
            .filter((value) => value);
    }

    areValidTriggerValues() {
        if (this.availableTriggerFieldValues.length === 0) {
            return true;
        }

        const validValues = new Set(this.availableTriggerFieldValues);
        const configuredValues = this.parseTriggerValues(this.outboundTriggerFieldValues);
        return configuredValues.every((value) => validValues.has(value));
    }

    get primaryHeaderNameLabel() {
        if (this.isHmacMode) {
            return 'Signature Header Name';
        }
        return 'Header Name';
    }

    get primaryHeaderNamePlaceholder() {
        if (this.isApiKeyMode) {
            return 'X-API-KEY';
        }
        if (this.isBearerMode || this.isBasicMode) {
            return 'Authorization';
        }
        if (this.isHmacMode) {
            return 'x-publicapi-signature';
        }
        return '';
    }

    get primaryHeaderValueLabel() {
        if (this.isApiKeyMode) {
            return 'API Key Value';
        }
        if (this.isBearerMode) {
            return 'Bearer Token';
        }
        if (this.isBasicMode) {
            return 'Username:Password';
        }
        return 'Header Value';
    }

    get primaryHeaderValuePlaceholder() {
        if (this.isApiKeyMode) {
            return 'Enter the outbound API key';
        }
        if (this.isBearerMode) {
            return 'Enter the bearer token';
        }
        if (this.isBasicMode) {
            return 'username:password';
        }
        return '';
    }

    get showPrimaryHeaderNameInput() {
        return !this.isNoAuthMode;
    }
}
