import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPayloadSettings from '@salesforce/apex/UnbounceJsonPayloadBuilderController.getPayloadSettings';
import getHeaderSettings from '@salesforce/apex/UnbounceJsonPayloadBuilderController.getHeaderSettings';
import savePayloadSettings from '@salesforce/apex/UnbounceJsonPayloadBuilderController.savePayloadSettings';
import saveHeaderSettings from '@salesforce/apex/UnbounceJsonPayloadBuilderController.saveHeaderSettings';

const DEFAULT_CONTENT_TYPE = 'application/json';
const VALUE_PLACEHOLDER = '$intake.litify_pm__First_Name__c';
const SUGGESTION_LIMIT = 12;

let headerCounter = 0;
let mappingCounter = 0;

export default class UnbounceJsonPayloadBuilder extends LightningElement {
    @api recordId;

    isLoading = false;
    errorMessage = '';
    isDirty = false;

    syncDirections = true;
    activePayloadScope = 'inbound';
    defaultPayloadSettings = { inbound: [], outbound: [] };
    availableFieldReferences = [];
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

    get payloadHelpText() {
        if (this.syncDirections) {
            return 'Inbound and outbound mappings stay in sync. Edit either tab and the other side mirrors automatically.';
        }
        return 'Inbound and outbound mappings are independent. Edit each tab separately.';
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

    get payloadPreviewTitle() {
        return this.activePayloadScope === 'outbound'
            ? 'Outbound Payload Preview'
            : 'Inbound Payload Preview';
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
            return `${this.headerName || 'x-unbounce-signature'}: ${this.hasWebhookSecret ? '[generated at send time]' : '[missing webhook secret]'}`;
        }
        return 'No auth header configured';
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
            this.availableFieldReferences = payloadSettings?.availableFieldReferences || [];
            this.defaultPayloadSettings = this.parsePayloadConfiguration(
                payloadSettings?.defaultJson || '{}'
            );

            const configuredPayloadSettings = this.parsePayloadConfiguration(
                payloadSettings?.configurationJson || payloadSettings?.defaultJson || '{}'
            );
            this.inboundMappingRows = configuredPayloadSettings.inbound;
            this.outboundMappingRows = configuredPayloadSettings.outbound;
            if (this.syncDirections) {
                if (this.inboundMappingRows.length > 0 && this.outboundMappingRows.length === 0) {
                    this.outboundMappingRows = this.cloneRows(this.inboundMappingRows);
                } else if (this.outboundMappingRows.length > 0 && this.inboundMappingRows.length === 0) {
                    this.inboundMappingRows = this.cloneRows(this.outboundMappingRows);
                }
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
                    configJson: JSON.stringify(this.buildPayloadConfiguration(), null, 2)
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
            if (this.inboundMappingRows.length > 0) {
                this.outboundMappingRows = this.cloneRows(this.inboundMappingRows);
            } else if (this.outboundMappingRows.length > 0) {
                this.inboundMappingRows = this.cloneRows(this.outboundMappingRows);
            }
        }
        this.isDirty = true;
    }

    handlePayloadTabActive(event) {
        this.activePayloadScope = event.target.value || 'inbound';
    }

    handleLoadDefaultMappings() {
        this.inboundMappingRows = this.cloneRows(this.defaultPayloadSettings.inbound);
        this.outboundMappingRows = this.cloneRows(this.defaultPayloadSettings.outbound);
        if (this.syncDirections) {
            this.outboundMappingRows = this.cloneRows(this.inboundMappingRows);
        }
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
        this.inboundMappingRows = [...this.inboundMappingRows, this.createMappingRow()];
        if (this.syncDirections) {
            this.outboundMappingRows = this.cloneRows(this.inboundMappingRows);
        }
        this.isDirty = true;
    }

    handleAddOutboundMappingRow() {
        this.outboundMappingRows = [...this.outboundMappingRows, this.createMappingRow()];
        if (this.syncDirections) {
            this.inboundMappingRows = this.cloneRows(this.outboundMappingRows);
        }
        this.isDirty = true;
    }

    handleMappingExternalKeyChange(event) {
        this.updateMappingRow(
            event.target.dataset.scope,
            event.target.dataset.id,
            { externalKey: event.target.value || '' }
        );
    }

    handleMappingValueInput(event) {
        this.updateMappingRow(
            event.target.dataset.scope,
            event.target.dataset.id,
            {
                value: event.target.value || '',
                showSuggestions: true
            }
        );
    }

    handleMappingValueFocus(event) {
        const scope = event.target.dataset.scope;
        const row = this.findMappingRow(scope, event.target.dataset.id);
        if (!row) {
            return;
        }
        this.updateMappingRow(scope, row.id, {
            showSuggestions: true,
            suggestions: this.getFilteredFieldSuggestions(row.value)
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
            suggestions: this.getFilteredFieldSuggestions(value)
        });
    }

    handleRemoveMapping(event) {
        this.removeMappingRow(event.currentTarget.dataset.scope, event.currentTarget.dataset.id);
    }

    createMappingRow(externalKey = '', value = '', sortOrder = 0) {
        mappingCounter++;
        return this.hydrateMappingRow({
            id: `mapping_${mappingCounter}`,
            externalKey,
            value,
            sortOrder,
            showSuggestions: false
        });
    }

    hydrateMappingRow(row) {
        const suggestions = this.getFilteredFieldSuggestions(row.value);
        return {
            ...row,
            suggestions,
            hasSuggestions: suggestions.length > 0
        };
    }

    parsePayloadConfiguration(configJson) {
        if (!configJson) {
            return { inbound: [], outbound: [] };
        }

        let parsed;
        try {
            parsed = JSON.parse(configJson);
        } catch (error) {
            return { inbound: [], outbound: [] };
        }
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
            return { inbound: [], outbound: [] };
        }

        return {
            inbound: this.parseMappingArray(parsed.inbound),
            outbound: this.parseMappingArray(parsed.outbound)
        };
    }

    parseMappingArray(rawMappings) {
        if (!Array.isArray(rawMappings)) {
            return [];
        }

        return rawMappings.map((row) =>
            this.createMappingRow(
                row.externalKey || '',
                row.value || '',
                Number.isFinite(Number(row.sortOrder)) ? Number(row.sortOrder) : 0
            )
        );
    }

    buildPayloadConfiguration() {
        const inbound = this.buildMappingArray(this.inboundMappingRows);
        const outbound = this.syncDirections
            ? this.buildMappingArray(this.inboundMappingRows)
            : this.buildMappingArray(this.outboundMappingRows);
        return {
            inbound,
            outbound
        };
    }

    buildPayloadPreview() {
        const rows = this.activePayloadScope === 'outbound'
            ? this.outboundMappingRows
            : this.inboundMappingRows;
        const preview = {};
        this.buildMappingArray(rows).forEach((row) => {
            preview[row.externalKey] = this.getPreviewValue(row.value);
        });
        return preview;
    }

    getPreviewValue(fieldReference) {
        const normalizedReference = (fieldReference || '').trim();
        if (!normalizedReference || !normalizedReference.startsWith('$intake.')) {
            return null;
        }

        const fieldApiName = normalizedReference.substring('$intake.'.length).toLowerCase();
        const previewValues = {
            'litify_pm__first_name__c': 'Jane',
            'litify_pm__last_name__c': 'Smith',
            'litify_pm__email__c': 'jane.smith@example.com',
            'litify_pm__phone__c': '(555) 123-4567',
            'litify_pm__description__c': 'Lead from Unbounce landing page',
            'litify_pm__lit_exact_source__c': 'https://example.com/landing',
            'litify_pm__utm_source__c': 'google',
            'litify_pm__utm_medium__c': 'cpc',
            'litify_pm__utm_campaign__c': 'summer-2025',
            'litify_pm__utm_content__c': 'ad-variant-a',
            'gclid__c': 'EAIaIQobChMI_test_gclid',
            'google_ads_conversion_time__c': '2026-03-03T05:38:21.000Z',
            'createddate': '2026-03-03T05:38:21.000Z',
            'litify_pm__turn_down_details__c': 'test test'
        };

        return fieldApiName in previewValues ? previewValues[fieldApiName] : null;
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
        if (scope === 'outbound') {
            this.outboundMappingRows = rows;
            if (this.syncDirections) {
                this.inboundMappingRows = this.cloneRows(rows);
            }
        } else {
            this.inboundMappingRows = rows;
            if (this.syncDirections) {
                this.outboundMappingRows = this.cloneRows(rows);
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

    cloneRows(rows) {
        return rows.map((row) =>
            this.createMappingRow(row.externalKey, row.value, row.sortOrder)
        );
    }

    getFilteredFieldSuggestions(searchTerm) {
        const normalizedSearchTerm = (searchTerm || '').trim().toLowerCase();
        const matches = this.availableFieldReferences.filter((reference) =>
            !normalizedSearchTerm || reference.toLowerCase().includes(normalizedSearchTerm)
        );
        return matches.slice(0, SUGGESTION_LIMIT).map((reference) => ({
            label: reference,
            value: reference
        }));
    }

    isValidFieldReference(value) {
        const normalizedValue = (value || '').trim();
        return !normalizedValue || this.availableFieldReferences.includes(normalizedValue);
    }

    clearSuggestionState() {
        this.inboundMappingRows = this.inboundMappingRows.map((row) =>
            this.hydrateMappingRow({ ...row, showSuggestions: false })
        );
        this.outboundMappingRows = this.outboundMappingRows.map((row) =>
            this.hydrateMappingRow({ ...row, showSuggestions: false })
        );
    }

    validateBeforeSave() {
        let isValid = true;
        this.errorMessage = '';

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
            const message = hasAnyValue && !(row?.externalKey || '').trim()
                ? 'External key is required.'
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
            const hasAnyValue = !!((row?.externalKey || '').trim() || (row?.value || '').trim());
            let message = '';
            if (hasAnyValue && !(row?.value || '').trim()) {
                message = 'Value is required.';
            } else if ((row?.value || '').trim() && !this.isValidFieldReference(row.value)) {
                message = 'Enter a valid Intake field reference, for example $intake.litify_pm__First_Name__c.';
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
            'X-Unbounce-Event-Type': 'status_changed'
        };

        if (this.authMode === 'ApiKeyHeader' && this.headerValue) {
            result[this.headerName || 'X-API-KEY'] = this.headerValue;
        } else if (this.authMode === 'BearerToken' && this.headerValue) {
            result[this.headerName || 'Authorization'] = `Bearer ${this.headerValue}`;
        } else if (this.authMode === 'BasicAuth' && this.headerValue) {
            result[this.headerName || 'Authorization'] = 'Basic [base64 encoded at send time]';
        } else if (this.authMode === 'HmacSignature') {
            result[this.headerName || 'x-unbounce-signature'] =
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

        const managedHeaderNames = new Set(['content-type', 'x-unbounce-event-type']);

        if (this.authMode === 'ApiKeyHeader') {
            managedHeaderNames.add((this.headerName || 'X-API-KEY').trim().toLowerCase());
        } else if (this.authMode === 'BearerToken' || this.authMode === 'BasicAuth') {
            managedHeaderNames.add((this.headerName || 'Authorization').trim().toLowerCase());
        } else if (this.authMode === 'HmacSignature') {
            managedHeaderNames.add((this.headerName || 'x-unbounce-signature').trim().toLowerCase());
        }

        return managedHeaderNames.has(normalizedName);
    }

    updateHeaderRow(rowId, field, value) {
        this.headerRows = this.headerRows.map((row) =>
            (row.id === rowId ? { ...row, [field]: value } : row)
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
            return 'x-unbounce-signature';
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

    get inputValuePlaceholder() {
        return VALUE_PLACEHOLDER;
    }
}
