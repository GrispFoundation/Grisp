import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";

export class ChatGPTAdapter extends ProviderAdapter {
    constructor() {
        super("chatgpt", "https://chatgpt.com/");
    }

    input(doc) {
        return this.findBySelectors(doc, ["#prompt-textarea", "textarea", '[contenteditable="true"][role="textbox"]']);
    }

    sendButton(doc) {
        return this.findBySelectors(doc, ['button[data-testid*="send"]', 'button[aria-label*="Send"]']);
    }

    responseNodes(doc) {
        return this.findAllBySelectors(doc, ['[data-message-author-role="assistant"] .markdown', '.agent-turn .markdown']);
    }

    isStreaming(doc) {
        return !!doc.querySelector('[data-testid="stop-button"],.result-streaming');
    }

    isAuthenticated(doc) {
        return !/(auth0|login|signin)/i.test(doc.location?.href || "");
    }
}
