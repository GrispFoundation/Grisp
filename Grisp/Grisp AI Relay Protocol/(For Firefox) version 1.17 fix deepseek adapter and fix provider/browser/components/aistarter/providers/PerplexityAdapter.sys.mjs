import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
export class PerplexityAdapter extends ProviderAdapter {
    constructor() {
        super("perplexity", "https://www.perplexity.ai/");
    }
    input(doc) {
        return this.findBySelectors(doc, ['textarea', '[contenteditable="true"]', '[placeholder*="Ask"]', '[placeholder*="anything"]']);
    }
    sendButton(doc) {
        return this.findBySelectors(doc, ['button[aria-label*="Submit"]', 'button[class*="send"]', 'button[aria-label*="Send"]', 'button[aria-label*="Ask"]']);
    }
    responseNodes(doc) {
        return this.findAllBySelectors(doc, [".prose", ".markdown", ".break-words"]);
    }
    isStreaming(doc) {
        return !!doc.querySelector('.loading-indicator,[class*="loading"]');
    }
}

