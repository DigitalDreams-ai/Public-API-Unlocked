import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PublicApiPrettyJson extends LightningElement {
    _jsonString = '';
    _fieldApiName = '';
    _colorTheme = 'default';

    formattedJson = '';
    hasError = false;
    errorMessage = '';
    collapsedPaths = new Set();

    @api recordId;

    @api
    get colorTheme() {
        return this._colorTheme;
    }

    set colorTheme(value) {
        const validThemes = ['black', 'warm', 'cool', 'default'];
        this._colorTheme = validThemes.includes(value) ? value : 'default';
    }

    get themeClass() {
        return `json-viewer theme-${this._colorTheme}`;
    }

    @api
    get jsonString() {
        return this._jsonString;
    }

    set jsonString(value) {
        this._jsonString = value || '';
        if (!this._fieldApiName) {
            this.formatJson();
        }
    }

    @api
    get fieldApiName() {
        return this._fieldApiName;
    }

    set fieldApiName(value) {
        this._fieldApiName = value || '';
        if (!this._fieldApiName && this._jsonString) {
            this.formatJson();
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fields' })
    wiredRecord({ error, data }) {
        if (!this._fieldApiName || !this.recordId) {
            return;
        }

        if (data) {
            try {
                const fieldValue = getFieldValue(data, this.fields[0]);
                this._jsonString = fieldValue === null || fieldValue === undefined ? '' : String(fieldValue);
                this.formatJson();
            } catch (err) {
                this.hasError = true;
                this.errorMessage = `Error reading field: ${err.message}`;
                this.formattedJson = '';
            }
        } else if (error) {
            this.hasError = true;
            this.errorMessage = error.body?.message || error.message || 'Error loading record data';
            this.formattedJson = '';
        }
    }

    get fields() {
        if (this.recordId && this._fieldApiName) {
            return [this._fieldApiName];
        }
        return [];
    }

    get hasErrorOrNoJson() {
        return this.hasError || !this._jsonString || this._jsonString.trim() === '';
    }

    connectedCallback() {
        this.formatJson();
    }

    formatJson() {
        const jsonToFormat = this._jsonString || '';
        if (!jsonToFormat || jsonToFormat.trim() === '') {
            this.formattedJson = '';
            this.hasError = false;
            return;
        }

        try {
            const parsed = JSON.parse(jsonToFormat);
            this.formattedJson = this.renderJson(parsed, '', 'root');
            this.hasError = false;
            this.errorMessage = '';
        } catch (error) {
            this.hasError = true;
            this.errorMessage = error.message;
            this.formattedJson = '';
        }
    }

    renderJson(obj, indent, path) {
        if (obj === null) {
            return '<span class="json-null">null</span>';
        }

        const type = Array.isArray(obj) ? 'array' : typeof obj;
        const isCollapsed = this.collapsedPaths.has(path);

        switch (type) {
            case 'object':
                return this.renderObject(obj, indent, path, isCollapsed);
            case 'array':
                return this.renderArray(obj, indent, path, isCollapsed);
            case 'string':
                return `<span class="json-string">"${this.escapeHtml(obj)}"</span>`;
            case 'number':
                return `<span class="json-number">${obj}</span>`;
            case 'boolean':
                return `<span class="json-boolean">${obj}</span>`;
            default:
                return `<span class="json-undefined">${String(obj)}</span>`;
        }
    }

    renderObject(obj, indent, path, isCollapsed) {
        const keys = Object.keys(obj);
        if (keys.length === 0) {
            return '<span class="json-brace">{</span> <span class="json-brace">}</span>';
        }

        const nextIndent = indent + '  ';
        const toggleIcon = isCollapsed ? '▶' : '▼';

        let html = `<span class="json-toggle" data-path="${path}" role="button" tabindex="0">${toggleIcon}</span> `;
        html += '<span class="json-brace">{</span>';

        if (!isCollapsed) {
            html += '<div class="json-content">';
            keys.forEach((key, index) => {
                const keyPath = path === 'root' ? key : `${path}.${key}`;
                html += `<div class="json-line" style="padding-left: ${indent.length}ch;">`;
                html += `<span class="json-key">"${this.escapeHtml(key)}"</span>: `;
                html += this.renderJson(obj[key], nextIndent, keyPath);
                if (index < keys.length - 1) {
                    html += ',';
                }
                html += '</div>';
            });
            html += '</div>';
            html += `<div class="json-line" style="padding-left: ${indent.length}ch;"><span class="json-brace">}</span></div>`;
        } else {
            html += ` <span class="json-collapsed">... ${keys.length} ${keys.length === 1 ? 'key' : 'keys'}</span> `;
            html += '<span class="json-brace">}</span>';
        }

        return html;
    }

    renderArray(arr, indent, path, isCollapsed) {
        if (arr.length === 0) {
            return '<span class="json-bracket">[</span> <span class="json-bracket">]</span>';
        }

        const nextIndent = indent + '  ';
        const toggleIcon = isCollapsed ? '▶' : '▼';

        let html = `<span class="json-toggle" data-path="${path}" role="button" tabindex="0">${toggleIcon}</span> `;
        html += '<span class="json-bracket">[</span>';

        if (!isCollapsed) {
            html += '<div class="json-content">';
            arr.forEach((item, index) => {
                const itemPath = `${path}[${index}]`;
                html += `<div class="json-line" style="padding-left: ${indent.length}ch;">`;
                html += this.renderJson(item, nextIndent, itemPath);
                if (index < arr.length - 1) {
                    html += ',';
                }
                html += '</div>';
            });
            html += '</div>';
            html += `<div class="json-line" style="padding-left: ${indent.length}ch;"><span class="json-bracket">]</span></div>`;
        } else {
            html += ` <span class="json-collapsed">... ${arr.length} ${arr.length === 1 ? 'item' : 'items'}</span> `;
            html += '<span class="json-bracket">]</span>';
        }

        return html;
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    handleToggleClick(event) {
        const path = event.currentTarget.getAttribute('data-path');
        if (this.collapsedPaths.has(path)) {
            this.collapsedPaths.delete(path);
        } else {
            this.collapsedPaths.add(path);
        }
        this.formatJson();
    }

    renderedCallback() {
        const container = this.template.querySelector('.json-output');
        if (!container) {
            return;
        }

        container.className = `json-output theme-${this._colorTheme}`;
        if (!this.formattedJson) {
            container.innerHTML = '';
            return;
        }

        container.innerHTML = this.formattedJson;
        const toggles = container.querySelectorAll('.json-toggle');
        toggles.forEach((toggle) => {
            toggle.addEventListener('click', (event) => {
                event.stopPropagation();
                this.handleToggleClick(event);
            });
            toggle.addEventListener('keydown', (event) => {
                if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    event.stopPropagation();
                    this.handleToggleClick(event);
                }
            });
        });
    }

    handleCopyToClipboard() {
        const jsonToCopy = this._jsonString || '';
        if (!jsonToCopy || jsonToCopy.trim() === '') {
            this.showToast('No JSON to copy', 'error');
            return;
        }

        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(jsonToCopy)
                .then(() => this.showToast('JSON copied to clipboard', 'success'))
                .catch(() => this.fallbackCopyToClipboard(jsonToCopy));
            return;
        }

        this.fallbackCopyToClipboard(jsonToCopy);
    }

    fallbackCopyToClipboard(text) {
        try {
            const textArea = document.createElement('textarea');
            textArea.value = text;
            textArea.style.position = 'fixed';
            textArea.style.left = '-999999px';
            textArea.style.top = '-999999px';
            textArea.style.opacity = '0';
            textArea.setAttribute('readonly', '');

            const container = this.template.querySelector('.json-viewer') || document.body;
            container.appendChild(textArea);
            textArea.select();
            textArea.setSelectionRange(0, text.length);

            const copied = document.execCommand('copy');
            container.removeChild(textArea);
            if (!copied) {
                throw new Error('Copy failed');
            }
            this.showToast('JSON copied to clipboard', 'success');
        } catch (error) {
            this.showToast('Failed to copy to clipboard. Please select and copy manually.', 'error');
        }
    }

    showToast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: variant === 'success' ? 'Success' : 'Error',
            message,
            variant,
            mode: 'dismissable'
        }));
    }
}
