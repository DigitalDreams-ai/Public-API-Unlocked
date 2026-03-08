import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPayloadSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getPayloadSettings';
import getHeaderSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getHeaderSettings';
import getFieldReferences from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getFieldReferences';
import getTriggerFieldNames from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getTriggerFieldNames';
import getTriggerFieldValues from '@salesforce/apex/PublicApiPayloadBuilderCtrl.getTriggerFieldValues';
import savePayloadSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.savePayloadSettings';
import saveHeaderSettings from '@salesforce/apex/PublicApiPayloadBuilderCtrl.saveHeaderSettings';

const DEFAULT_CONTENT_TYPE = 'application/json';
const DEFAULT_OBJECT_API_NAME = 'PublicApi_Submission__c';
const SUGGESTION_LIMIT = 12;

let headerCounter = 0;
let mappingCounter = 0;

export default class PublicApiJsonPayloadBuilder extends LightningElement {
    @api recordId;

    isLoading = false;
    errorMessage = '';
    isDirty = false;

    syncDirections = true;
    activePayloadScope = 'inbound';
    defaultInboundRows = [];
    defaultOutboundRows = [];
    targetObjectApiName = DEFAULT_OBJECT_API_NAME;
    targetObjectSearchValue = DEFAULT_OBJECT_API_NAME;
    showObjectSuggestions = false;
    availableObjectApiNames = [];
    availableInboundFieldReferences = [];
    availableOutboundFieldReferences = [];
    outboundTriggerEnabled = true;
    outboundTriggerFieldName = '';
    outboundTriggerFieldValues = '';
    showTriggerFieldSuggestions = false;
    showTriggerValueSuggestions = false;
    availableTriggerFieldNames = [];
    availableTriggerFieldValues = [];
    inboundMappingRows = [];
    outboundMappingRows = [];
    authMode = 'None';
    contentType = DEFAULT_CONTENT_TYPE;
    headerName = '';
    headerValue = '';
    hasWebhookSecret = false;
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

    get valuePlaceholder() {
        return `$${this.targetObjectApiName || DEFAULT_OBJECT_API_NAME}.Status__c`;
    }

    get payloadHelpText() {
        return this.syncDirections
            ? 'Inbound and outbound mappings stay in sync. Edit either tab and the other side mirrors automatically.'
            : 'Inbound and outbound mappings are independent. Edit each tab separately.';
    }

    get hasInboundMappingRows() {
        return this.inboundMappingRows.length > 0;
    }

    get hasOutboundMappingRows() {
        return this.outboundMappingRows.length > 0;
    }

    get mappingPreviewJson() {
        return JSON.stringify(this.buildPayloadPreview(), null, 2);
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
            return 'This header carries the generated request signature. The signature value comes from Outbound Webhook Secret.';
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
            this.targetObjectApiName = payloadSettings?.targetObjectApiName || DEFAULT_OBJECT_API_NAME;
            this.targetObjectSearchValue = this.targetObjectApiName;
            this.availableObjectApiNames = payloadSettings?.availableObjectApiNames || [];
            this.availableInboundFieldReferences = payloadSettings?.availableInboundFieldReferences || [];
            this.availableOutboundFieldReferences = payloadSettings?.availableOutboundFieldReferences || [];
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

            this.inboundMappingRows = this.parseMappingArray(
                'inbound',
                payloadSettings?.inboundConfigurationJson || payloadSettings?.defaultInboundJson
            );
            this.outboundMappingRows = this.parseMappingArray(
                'outbound',
                payloadSettings?.outboundConfigurationJson || payloadSettings?.defaultOutboundJson
            );
            if (this.syncDirections) {
                this.outboundMappingRows = this.cloneRows(this.inboundMappingRows, 'outbound');
            }

            this.authMode = headerSettings?.authMode || 'None';
            this.contentType = headerSettings?.contentType || DEFAULT_CONTENT_TYPE;
            this.headerName = headerSettings?.headerName || '';
            this.headerValue = headerSettings?.headerValue || '';
            this.hasWebhookSecret = !!headerSettings?.hasWebhookSecret;
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
                    targetObjectApiName: this.targetObjectApiName,
                    outboundTriggerEnabled: this.outboundTriggerEnabled,
                    outboundTriggerFieldName: this.outboundTriggerFieldName,
                    outboundTriggerFieldValues: this.outboundTriggerFieldValues,
                    inboundConfigJson: JSON.stringify(this.buildMappingArray(this.inboundMappingRows), null, 2),
                    outboundConfigJson: JSON.stringify(
                        this.syncDirections
                            ? this.buildMappingArray(this.inboundMappingRows)
                            : this.buildMappingArray(this.outboundMappingRows),
                        null,
                        2
                    )
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

    handleTargetObjectInput(event) {
        this.targetObjectSearchValue = event.target.value || '';
        this.trySelectTargetObjectValue(this.targetObjectSearchValue);
        this.showObjectSuggestions = true;
    }

    handleTargetObjectFocus() {
        this.showObjectSuggestions = true;
    }

    handleTargetObjectBlur() {
        window.setTimeout(() => {
            this.showObjectSuggestions = false;
            if (this.trySelectTargetObjectValue(this.targetObjectSearchValue)) {
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
        this.showObjectSuggestions = false;
        this.targetObjectApiName = value;
        this.targetObjectSearchValue = value;
        await this.refreshMetadataForTargetObject();
        this.inboundMappingRows = this.rehydrateRowsForScope('inbound', this.inboundMappingRows);
        this.outboundMappingRows = this.rehydrateRowsForScope('outbound', this.outboundMappingRows);
        this.isDirty = true;
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
        this.inboundMappingRows = this.cloneRows(this.defaultInboundRows, 'inbound');
        this.outboundMappingRows = this.syncDirections
            ? this.cloneRows(this.defaultInboundRows, 'outbound')
            : this.cloneRows(this.defaultOutboundRows, 'outbound');
        this.errorMessage = '';
        this.isDirty = true;
    }

    handleClearInboundMappings() {
        this.inboundMappingRows = [];
        if (this.syncDirections) {
            this.outboundMappingRows = [];
        }
        this.errorMessage = '';
        this.isDirty = true;
    }

    handleClearOutboundMappings() {
        this.outboundMappingRows = [];
        if (this.syncDirections) {
            this.inboundMappingRows = [];
        }
        this.errorMessage = '';
        this.isDirty = true;
    }

    handleAddInboundMappingRow() {
        this.inboundMappingRows = [...this.inboundMappingRows, this.createMappingRow('inbound')];
        if (this.syncDirections) {
            this.outboundMappingRows = this.cloneRows(this.inboundMappingRows, 'outbound');
        }
        this.isDirty = true;
    }

    handleAddOutboundMappingRow() {
        this.outboundMappingRows = [...this.outboundMappingRows, this.createMappingRow('outbound')];
        if (this.syncDirections) {
            this.inboundMappingRows = this.cloneRows(this.outboundMappingRows, 'inbound');
        }
        this.isDirty = true;
    }

    handleMappingExternalKeyChange(event) {
        this.updateMappingRow(event.target.dataset.scope, event.target.dataset.id, {
            externalKey: event.target.value || ''
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

    createMappingRow(scope, externalKey = '', value = '', sortOrder = 0) {
        mappingCounter++;
        return this.hydrateMappingRow({
            id: `mapping_${mappingCounter}`,
            externalKey,
            value,
            scope: scope || 'inbound',
            sortOrder,
            showSuggestions: false
        });
    }

    hydrateMappingRow(row) {
        const scope = row?.scope || 'inbound';
        const suggestions = this.getFilteredFieldSuggestions(scope, row.value);
        return {
            ...row,
            scope,
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
                Number.isFinite(Number(row.sortOrder)) ? Number(row.sortOrder) : 0
            )
        );
    }

    buildPayloadPreview() {
        const rows = this.activePayloadScope === 'outbound' ? this.outboundMappingRows : this.inboundMappingRows;
        const preview = {};
        this.buildMappingArray(rows).forEach((row) => {
            preview[row.externalKey] = this.getPreviewValue(row.value);
        });
        return preview;
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
                sortOrder: index + 1
            }))
            .filter((row) => row.externalKey && row.value);
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
                this.inboundMappingRows = this.cloneRows(normalizedRows, 'inbound');
            }
        } else {
            this.inboundMappingRows = normalizedRows;
            if (this.syncDirections) {
                this.outboundMappingRows = this.cloneRows(normalizedRows, 'outbound');
            }
        }
        this.isDirty = true;
    }

    getRowsForScope(scope) {
        return scope === 'outbound' ? this.outboundMappingRows : this.inboundMappingRows;
    }

    findMappingRow(scope, rowId) {
        return this.getRowsForScope(scope).find((row) => row.id === rowId);
    }

    cloneRows(rows, targetScope) {
        return rows.map((row) =>
            this.createMappingRow(targetScope || row.scope, row.externalKey, row.value, row.sortOrder)
        );
    }

    rehydrateRowsForScope(scope, rows) {
        return (rows || []).map((row) =>
            this.hydrateMappingRow({
                ...row,
                scope
            })
        );
    }

    getFieldReferenceOptions(scope) {
        return scope === 'outbound' ? this.availableOutboundFieldReferences : this.availableInboundFieldReferences;
    }

    trySelectTargetObjectValue(value) {
        const normalizedValue = (value || '').trim();
        if (!normalizedValue) {
            return false;
        }

        const matchedValue = this.availableObjectApiNames.find(
            (option) => option.toLowerCase() === normalizedValue.toLowerCase()
        );
        if (!matchedValue) {
            return false;
        }

        this.targetObjectApiName = matchedValue;
        this.targetObjectSearchValue = matchedValue;
        return true;
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

    clearSuggestionState() {
        this.inboundMappingRows = this.inboundMappingRows.map((row) =>
            this.hydrateMappingRow({ ...row, showSuggestions: false })
        );
        this.outboundMappingRows = this.outboundMappingRows.map((row) =>
            this.hydrateMappingRow({ ...row, showSuggestions: false })
        );
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
        const valueInputs = this.template.querySelectorAll('lightning-input[data-role="mapping-value"]');

        externalKeyInputs.forEach((input) => {
            const scope = input.dataset.scope;
            if (!validateScopes.includes(scope)) {
                input.setCustomValidity('');
                input.reportValidity();
                return;
            }
            const row = rowsByScope[scope].get(input.dataset.id);
            const hasAnyValue = !!((row?.externalKey || '').trim() || (row?.value || '').trim());
            const message = hasAnyValue && !(row?.externalKey || '').trim() ? 'External key is required.' : '';
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
            const hasAnyValue = !!((row?.externalKey || '').trim() || (row?.value || '').trim());
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

        if (!isValid) {
            this.errorMessage = 'Fix the payload mapping rows before saving.';
        }
        return isValid;
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
            this.refreshFieldReferences(),
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

    async refreshTriggerFieldNames() {
        try {
            this.availableTriggerFieldNames = await getTriggerFieldNames({
                objectApiName: this.targetObjectApiName
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
                objectApiName: this.targetObjectApiName,
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

    areValidTriggerValues() {
        if (this.availableTriggerFieldValues.length === 0) {
            return true;
        }

        const validValues = new Set(this.availableTriggerFieldValues);
        const configuredValues = (this.outboundTriggerFieldValues || '')
            .replace(/\r/g, '\n')
            .replace(/;/g, ',')
            .split(/[,\n]+/)
            .map((value) => value.trim())
            .filter((value) => value);
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
