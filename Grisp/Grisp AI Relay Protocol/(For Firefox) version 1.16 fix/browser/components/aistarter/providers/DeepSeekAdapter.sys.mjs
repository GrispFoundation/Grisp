import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
import { garpDebug } from "../GarpDebug.sys.mjs";

export class DeepSeekAdapter extends ProviderAdapter {
    constructor() {
        super("deepseek", "https://chat.deepseek.com/");
    }

    input(doc) {
        const selectors = [
            "textarea.ds-input__input",
            "textarea#chat-input",
            'textarea[placeholder*="DeepSeek"]',
            "textarea",
        ];
        const result = this.findBySelectors(doc, selectors);
        garpDebug(2, "DeepSeek input result", {
            found: !!result,
            tag: result?.tagName || null,
            id: result?.id || null,
            classes: String(result?.className || ""),
            placeholder: result?.getAttribute?.("placeholder") || null,
            disabled: !!result?.disabled,
        });
        return result;
    }

    sendButton(doc) {
        const selectors = [
            'div[role="button"].ds-icon-button',
            "button.ds-icon-button",
            'button[aria-label*="Send"]',
            '[data-testid*="send"]',
        ];
        const result = this.findBySelectors(doc, selectors);
        garpDebug(2, "DeepSeek send button result", {
            found: !!result,
            tag: result?.tagName || null,
            id: result?.id || null,
            classes: String(result?.className || ""),
            text: String(result?.textContent || "").trim().slice(0, 120),
            aria_label: result?.getAttribute?.("aria-label") || null,
        });
        return result;
    }

    responseNodes(doc) {
        const selectors = [".ds-markdown", ".ds-message-bubble"];
        const result = this.findAllBySelectors(doc, selectors);
        garpDebug(2, "DeepSeek response nodes", {
            count: result.length,
            url: doc?.location?.href || "",
        });
        return result;
    }

    isStreaming(doc) {
        const result = !!doc.querySelector(
            '.ds-loading,[class*="loading"],.spinner,[class*="spinner"],[data-streaming="true"]'
        );
        garpDebug(2, "DeepSeek streaming state", {
            streaming: result,
        });
        return result;
    }

    isAuthenticated(doc) {
        const url = doc.location?.href || "";
        const result = !/(login|sign_in|auth)/i.test(url);
        garpDebug(2, "DeepSeek authentication state", {
            authenticated: result,
            url,
        });
        return result;
    }

    isRateLimited(doc) {
        const body = doc.body?.innerText || "";
        const result = /rate.?limit|too many requests/i.test(body);
        garpDebug(2, "DeepSeek rate-limit state", {
            rate_limited: result,
            body_length: body.length,
        });
        return result;
    }
}
