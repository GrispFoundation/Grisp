import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
export class DeepSeekAdapter extends ProviderAdapter {
    constructor() {
        super("deepseek", "https://chat.deepseek.com/");
    }
    input(doc) {
        return this.findBySelectors(doc, ["textarea.ds-input__input", "textarea#chat-input", 'textarea[placeholder*="DeepSeek"]', "textarea"]);
    }
    sendButton(doc) {
        return this.findBySelectors(doc, ['div[role="button"].ds-icon-button', 'button.ds-icon-button', 'button[aria-label*="Send"]', '[data-testid*="send"]']);
    }
    responseNodes(doc) {
        return this.findAllBySelectors(doc, [".ds-markdown", ".ds-message-bubble"]);
    }
    isStreaming(doc) {
        return !!doc.querySelector('.ds-loading,[class*="loading"],.spinner,[class*="spinner"],[data-streaming="true"]');
    }
    isAuthenticated(doc) {
        return !/(login|sign_in|auth)/i.test(doc.location?.href || "");
    }
    isRateLimited(doc) {
        return /rate.?limit|too many requests/i.test(doc.body?.innerText || "");
    }
}

