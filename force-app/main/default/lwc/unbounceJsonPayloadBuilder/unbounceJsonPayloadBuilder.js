import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDefaultPayloadSchema from '@salesforce/apex/UnbounceJsonPayloadBuilderController.getDefaultPayloadSchema';
import getConfiguration from '@salesforce/apex/UnbounceJsonPayloadBuilderController.getConfiguration';
import getHeaderSettings from '@salesforce/apex/UnbounceJsonPayloadBuilderController.getHeaderSettings';
import saveConfiguration from '@salesforce/apex/UnbounceJsonPayloadBuilderController.saveConfiguration';
import saveHeaderSettings from '@salesforce/apex/UnbounceJsonPayloadBuilderController.saveHeaderSettings';

let nodeCounter = 0;
let headerCounter = 0;

export default class UnbounceJsonPayloadBuilder extends LightningElement {
    @api recordId;

    sourceSchema = null;
    templateTree = [];
    availablePaths = [];
    headerRows = [];
    isLoading = false;
    errorMessage = '';
    pasteValue = '';
    isDirty = false;
    authMode = 'None';
    contentType = 'application/json';
    headerName = '';
    headerValue = '';
    hasWebhookSecret = false;

    get authModeOptions() {
        return [
            { label: 'None', value: 'None' },
            { label: 'API Key Header', value: 'ApiKeyHeader' },
            { label: 'Bearer Token', value: 'BearerToken' },
            { label: 'Basic Auth', value: 'BasicAuth' },
            { label: 'HMAC Signature', value: 'HmacSignature' }
        ];
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

    get showPrimaryHeaderNameInput() {
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
            return 'No primary auth header will be added. Use Additional Headers below only if the receiver needs non-auth custom headers.';
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

    get primaryHeaderNameLabel() {
        if (this.isHmacMode) {
            return 'Signature Header Name';
        }
        if (this.isBearerMode || this.isBasicMode || this.isApiKeyMode) {
            return 'Primary Header Name';
        }
        return 'Header Name';
    }

    get primaryHeaderValueLabel() {
        if (this.isBearerMode) {
            return 'Token';
        }
        if (this.isBasicMode) {
            return 'Username:Password';
        }
        if (this.isApiKeyMode) {
            return 'Header Value';
        }
        if (this.isHmacMode) {
            return 'Signature Value';
        }
        return 'Header Value';
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

    get primaryHeaderValuePlaceholder() {
        if (this.isBearerMode) {
            return 'Paste token';
        }
        if (this.isBasicMode) {
            return 'username:password';
        }
        if (this.isApiKeyMode) {
            return 'Paste API key';
        }
        if (this.isHmacMode) {
            return 'Generated from Outbound Webhook Secret';
        }
        return '';
    }

    get authGuidanceTitle() {
        if (this.isNoAuthMode) {
            return 'No auth header will be sent';
        }
        if (this.isApiKeyMode) {
            return 'API key header';
        }
        if (this.isBearerMode) {
            return 'Bearer token header';
        }
        if (this.isBasicMode) {
            return 'Basic authorization header';
        }
        if (this.isHmacMode) {
            return 'HMAC signature header';
        }
        return 'Header configuration';
    }

    get authGuidanceBody() {
        if (this.isNoAuthMode) {
            return 'Use this when the receiver does not require authentication headers.';
        }
        if (this.isApiKeyMode) {
            return 'The builder sends one header using the configured name and value. Leave the name blank to default to X-API-KEY.';
        }
        if (this.isBearerMode) {
            return 'The builder sends Bearer <token>. Leave the name blank to default to Authorization.';
        }
        if (this.isBasicMode) {
            return 'Enter username:password. The builder base64-encodes it and sends Basic <encoded>. Leave the name blank to default to Authorization.';
        }
        if (this.isHmacMode) {
            return 'The builder generates the signature from Outbound Webhook Secret. Header Value is not used in this mode.';
        }
        return '';
    }

    get hasTemplateNodes() {
        return this.templateTree && this.templateTree.length > 0;
    }

    get hasHeaderRows() {
        return this.headerRows && this.headerRows.length > 0;
    }

    get isSaveDisabled() {
        return this.isLoading || !this.isDirty;
    }

    get pastePlaceholder() {
        return '{"lead":{"first_name":"$.firstName","email":"$.email"}}';
    }

    get isPasteEmpty() {
        return !this.pasteValue || this.pasteValue.trim() === '';
    }

    get payloadPreviewJson() {
        try {
            return JSON.stringify(this.buildOutputFromTree(this.templateTree), null, 2);
        } catch (e) {
            return '{}';
        }
    }

    get headersPreviewJson() {
        try {
            return JSON.stringify(this.buildEffectiveHeadersObject(), null, 2);
        } catch (e) {
            return '{}';
        }
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
            const [schemaJson, configJson, headerSettings] = await Promise.all([
                getDefaultPayloadSchema(),
                getConfiguration({ recordId: this.recordId }),
                getHeaderSettings({ recordId: this.recordId })
            ]);

            this.sourceSchema = JSON.parse(schemaJson);
            this.availablePaths = this.flattenPaths(this.sourceSchema, '$');
            this.templateTree = this.jsonToTree(configJson ? JSON.parse(configJson) : this.sourceSchema);
            this.authMode = headerSettings?.authMode || 'None';
            this.contentType = headerSettings?.contentType || 'application/json';
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

    handleLoadDefault() {
        if (!this.sourceSchema) {
            return;
        }
        this.templateTree = this.jsonToTree(this.sourceSchema);
        this.isDirty = true;
    }

    handleClear() {
        this.templateTree = [];
        this.pasteValue = '';
        this.isDirty = true;
    }

    handlePasteChange(event) {
        this.pasteValue = event.target.value;
    }

    handleParseJson() {
        this.errorMessage = '';
        try {
            const parsed = JSON.parse(this.pasteValue);
            if (typeof parsed !== 'object' || Array.isArray(parsed) || !parsed) {
                this.errorMessage = 'JSON must be an object, not an array or primitive.';
                return;
            }
            this.templateTree = this.jsonToTree(parsed);
            this.pasteValue = '';
            this.isDirty = true;
        } catch (error) {
            this.errorMessage = 'Invalid JSON: ' + error.message;
        }
    }

    async handleSave() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            let configJson = null;
            if (this.hasTemplateNodes) {
                configJson = JSON.stringify(this.buildOutputFromTree(this.templateTree), null, 2);
            }

            const headersJson = this.headersPreviewJson;

            await Promise.all([
                saveConfiguration({
                    recordId: this.recordId,
                    configJson
                }),
                saveHeaderSettings({
                    recordId: this.recordId,
                    authMode: this.authMode,
                    contentType: this.contentType,
                    headerName: this.headerName,
                    headerValue: this.headerValue,
                    additionalHeadersJson: headersJson
                })
            ]);

            this.isDirty = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Request builder configuration saved.',
                variant: 'success'
            }));
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: this.errorMessage,
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    handleAddRootNode() {
        this.templateTree = [...this.templateTree, this.createNode('newKey', '', 'string')];
        this.isDirty = true;
    }

    handleRemoveNode(event) {
        this.templateTree = this.removeNodeFromTree(this.templateTree, event.detail.nodeId);
        this.isDirty = true;
    }

    handleUpdateNode(event) {
        const { nodeId, field, value } = event.detail;
        this.templateTree = this.updateNodeInTree(this.templateTree, nodeId, field, value);
        this.isDirty = true;
    }

    handleAddChild(event) {
        this.templateTree = this.addChildToNode(this.templateTree, event.detail.nodeId);
        this.isDirty = true;
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
        this.contentType = event.target.value;
        this.isDirty = true;
    }

    handlePrimaryHeaderNameChange(event) {
        this.headerName = event.target.value;
        this.isDirty = true;
    }

    handlePrimaryHeaderValueChange(event) {
        this.headerValue = event.target.value;
        this.isDirty = true;
    }

    handleClearHeaders() {
        this.headerRows = [];
        this.isDirty = true;
    }

    handleHeaderNameChange(event) {
        this.updateHeaderRow(event.target.dataset.id, 'name', event.target.value);
    }

    handleHeaderValueChange(event) {
        this.updateHeaderRow(event.target.dataset.id, 'value', event.target.value);
    }

    handleRemoveHeader(event) {
        const rowId = event.currentTarget.dataset.id;
        this.headerRows = this.headerRows.filter((row) => row.id !== rowId);
        this.isDirty = true;
    }

    createNode(key, sourcePath, type) {
        nodeCounter++;
        return {
            id: `node_${nodeCounter}`,
            key,
            sourcePath: sourcePath || '',
            type: type || 'string',
            children: [],
            expanded: true
        };
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

        const parsed = JSON.parse(configJson);
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
        (this.headerRows || []).forEach((row) => {
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
            'Content-Type': this.contentType || 'application/json',
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

        const managedHeaderNames = new Set([
            'content-type',
            'x-unbounce-event-type'
        ]);

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
        this.headerRows = this.headerRows.map((row) => (
            row.id === rowId ? { ...row, [field]: value } : row
        ));
        this.isDirty = true;
    }

    jsonToTree(obj) {
        if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
            return [];
        }

        return Object.keys(obj).map((key) => this.valueToNode(key, obj[key]));
    }

    valueToNode(key, value) {
        if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
            const node = this.createNode(key, '', 'object');
            node.children = this.jsonToTree(value);
            return node;
        }

        const type = value === null ? 'null' :
            typeof value === 'number' ? 'number' :
            typeof value === 'boolean' ? 'boolean' : 'string';
        return this.createNode(
            key,
            typeof value === 'string' ? value : value === null ? '' : String(value),
            type
        );
    }

    buildOutputFromTree(nodes) {
        const result = {};
        (nodes || []).forEach((node) => {
            if (node.type === 'object') {
                result[node.key] = this.buildOutputFromTree(node.children || []);
            } else if (node.type === 'null') {
                result[node.key] = null;
            } else if (node.type === 'number') {
                const num = Number(node.sourcePath);
                result[node.key] = Number.isNaN(num) ? node.sourcePath : num;
            } else if (node.type === 'boolean') {
                result[node.key] = node.sourcePath === 'true';
            } else {
                result[node.key] = node.sourcePath || '';
            }
        });
        return result;
    }

    removeNodeFromTree(nodes, nodeId) {
        return nodes
            .filter((node) => node.id !== nodeId)
            .map((node) => ({
                ...node,
                children: node.children ? this.removeNodeFromTree(node.children, nodeId) : []
            }));
    }

    updateNodeInTree(nodes, nodeId, field, value) {
        return nodes.map((node) => {
            if (node.id === nodeId) {
                const updated = { ...node, [field]: value };
                if (field === 'type' && value === 'object' && (!node.children || node.children.length === 0)) {
                    updated.children = [];
                    updated.sourcePath = '';
                }
                if (field === 'type' && value !== 'object') {
                    updated.children = [];
                }
                return updated;
            }
            return {
                ...node,
                children: node.children ? this.updateNodeInTree(node.children, nodeId, field, value) : []
            };
        });
    }

    addChildToNode(nodes, parentId) {
        return nodes.map((node) => {
            if (node.id === parentId) {
                return {
                    ...node,
                    type: 'object',
                    expanded: true,
                    children: [...(node.children || []), this.createNode('newKey', '', 'string')]
                };
            }
            return {
                ...node,
                children: node.children ? this.addChildToNode(node.children, parentId) : []
            };
        });
    }

    flattenPaths(obj, prefix) {
        const paths = [];
        if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
            return paths;
        }

        Object.keys(obj).forEach((key) => {
            const fullPath = `${prefix}.${key}`;
            paths.push({ label: fullPath, value: fullPath });
            const value = obj[key];
            if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
                paths.push(...this.flattenPaths(value, fullPath));
            }
        });
        return paths;
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
}
