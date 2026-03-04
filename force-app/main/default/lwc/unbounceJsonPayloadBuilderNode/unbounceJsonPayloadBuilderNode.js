import { LightningElement, api } from 'lwc';

const MAX_SUGGESTIONS = 50;

export default class UnbounceJsonPayloadBuilderNode extends LightningElement {
    @api node;
    @api availablePaths = [];
    @api depth = 0;

    filterText = '';
    isFocused = false;

    get childDepth() {
        return Number(this.depth) + 1;
    }

    get nodeStyle() {
        return `padding-left: ${Number(this.depth) * 16}px`;
    }

    get isObject() {
        return this.node && this.node.type === 'object';
    }

    get isNull() {
        return this.node && this.node.type === 'null';
    }

    get showChildren() {
        return this.isObject && this.node.expanded && this.node.children && this.node.children.length > 0;
    }

    get expandIcon() {
        return this.node && this.node.expanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get typeOptions() {
        return [
            { label: 'String', value: 'string' },
            { label: 'Object', value: 'object' },
            { label: 'Number', value: 'number' },
            { label: 'Boolean', value: 'boolean' },
            { label: 'Null', value: 'null' }
        ];
    }

    get showSuggestions() {
        return this.isFocused && this.filteredPaths.length > 0;
    }

    get filteredPaths() {
        const text = (this.filterText || this.node?.sourcePath || '').toLowerCase();
        if (!this.availablePaths || this.availablePaths.length === 0) {
            return [];
        }

        if (!text || text === '$' || text === '$.') {
            return this.availablePaths.slice(0, MAX_SUGGESTIONS);
        }

        const matches = [];
        for (const suggestion of this.availablePaths) {
            if (
                suggestion.value.toLowerCase().includes(text) ||
                suggestion.label.toLowerCase().includes(text)
            ) {
                matches.push(suggestion);
                if (matches.length >= MAX_SUGGESTIONS) {
                    break;
                }
            }
        }
        return matches;
    }

    handleKeyChange(event) {
        this.dispatchUpdate('key', event.target.value);
    }

    handleTypeChange(event) {
        this.dispatchUpdate('type', event.detail.value);
    }

    handleSourcePathInputChange(event) {
        this.dispatchUpdate('sourcePath', event.target.value);
    }

    handleInputFocus() {
        this.isFocused = true;
        this.filterText = this.node?.sourcePath || '';
    }

    handleInputBlur() {
        setTimeout(() => {
            this.isFocused = false;
        }, 200);
    }

    handleInputFilter(event) {
        this.filterText = event.target.value;
    }

    handleSuggestionSelect(event) {
        this.isFocused = false;
        this.filterText = event.currentTarget.dataset.value;
        this.dispatchUpdate('sourcePath', event.currentTarget.dataset.value);
    }

    handleToggleExpand() {
        this.dispatchUpdate('expanded', !this.node.expanded);
    }

    handleAddChild() {
        this.dispatchEvent(new CustomEvent('addchild', {
            bubbles: true,
            composed: true,
            detail: { nodeId: this.node.id }
        }));
    }

    handleRemove() {
        this.dispatchEvent(new CustomEvent('removenode', {
            bubbles: true,
            composed: true,
            detail: { nodeId: this.node.id }
        }));
    }

    dispatchUpdate(field, value) {
        this.dispatchEvent(new CustomEvent('updatenode', {
            bubbles: true,
            composed: true,
            detail: {
                nodeId: this.node.id,
                field,
                value
            }
        }));
    }

    handleChildEvent() {}
}
