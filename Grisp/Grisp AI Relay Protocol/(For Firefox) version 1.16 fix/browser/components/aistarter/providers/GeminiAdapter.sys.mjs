import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
export class GeminiAdapter extends ProviderAdapter {
    constructor() {
        super("gemini", "https://gemini.google.com/app");
    }
    input(doc) {
        return this.findBySelectors(doc, [".ql-editor", "textarea", '[contenteditable="true"]']);
    }
    sendButton(doc) {
        return this.findBySelectors(doc, ['button[aria-label*="Send"]', 'button[aria-label*="send"]']);
    }
    responseNodes(doc) {
        return this.findAllBySelectors(doc, ["model-response .markdown", ".model-response-text .markdown", ".response-container .markdown", "model-response", ".message-content.model .markdown"]);
    }
    isStreaming(doc) {
        return !!doc.querySelector('button[aria-label*="Stop"],.loading-indicator,mat-progress-bar,.response-loading');
    }
    isAuthenticated(doc) {
        return !/(accounts.google.com|signin)/i.test(doc.location?.href || "");
    }
}

