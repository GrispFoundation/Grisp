export class ProviderAdapter {
    constructor(name, url) {
        this.name = name;
        this.url = url;
        this.adapter_version = "1.24.0";
        this.selector_strategy_version = "1.24.0";
        this.supported_features = ["streaming", "cancel", "continuation", "diagnostics"];
    }

    inputStrategies(_doc) {
        return ["keyboard_enter", "provider_native_send"];
    }

    supportsContinuation(_doc) {
        return true;
    }

    matchesDocument(doc) {
        try {
            const e = new URL(this.url), a = new URL(doc.location?.href || "");
            return a.protocol === e.protocol && (a.hostname === e.hostname || a.hostname.endsWith(`.${e.hostname}`));
        }
        catch (_) {
            return false;
        }
    }

    deepQuerySelectorAll(doc, selector) {
        const result = Array.from(doc.querySelectorAll(selector)), roots = new Set();
        const walk = root => {
            if (!root || roots.has(root))
                return;
            roots.add(root);
            for (const e of root.querySelectorAll?.("*") || []) {
                if (e.shadowRoot) {
                    result.push(...e.shadowRoot.querySelectorAll(selector));
                    walk(e.shadowRoot);
                }
            }
        };
        walk(doc);
        return [...new Set(result)];
    }

    visible(e) {
        return !!e && !!((e.offsetWidth > 0 || e.offsetHeight > 0 || e.getClientRects?.().length > 0) && e.style?.display !== "none" && e.style?.visibility !== "hidden");
    }

    enabled(e) {
        return !!e && !e.disabled && e.getAttribute("aria-disabled") !== "true";
    }

    findBySelectors(doc, s) {
        for (const sel of s)
            for (const e of this.deepQuerySelectorAll(doc, sel))
                if (this.visible(e) && this.enabled(e))
                    return e;
        return null;
    }

    findAllBySelectors(doc, s) {
        const r = [];
        for (const sel of s)
            r.push(...this.deepQuerySelectorAll(doc, sel));
        return [...new Set(r)].filter(e => this.visible(e));
    }

    findContinueButton(doc) {
        const sels = ['button[data-testid*="continue"]', 'button[aria-label*="Continue"]', 'button[aria-label*="continue"]', 'button', '[role=button]'];
        const is = t => { const v = String(t || "").trim().toLowerCase(); return v === "continue" || v.startsWith("continue") || v === "继续" || v.includes("继续生成") || v === "continuer" || v === "continuar" || v === "weiter"; };
        for (const e of this.findAllBySelectors(doc, sels).reverse())
            if (is(e.textContent) || is(e.getAttribute("aria-label")))
                return e;
        return null;
    }

    input(doc) {
        return this.findBySelectors(doc, ["textarea", '[contenteditable="true"]']);
    }

    sendButton(doc) {
        return this.findBySelectors(doc, ['button[aria-label*="Send"]', 'button[aria-label*="Submit"]', 'button[type="submit"]', '[data-testid*="send"]']);
    }

    responseNodes(doc) {
        return this.findAllBySelectors(doc, [".markdown", '[data-message-author-role="assistant"]']);
    }

    isStreaming(doc) {
        return !!doc.querySelector('[data-streaming="true"],.loading-indicator,.spinner,button[aria-label*="Stop"],[data-testid*="stop"]');
    }

    isAuthenticated(_doc) {
        return true;
    }

    isRateLimited(_doc) {
        return false;
    }

    dispatchInputEvent(input, prompt) {
        try {
            input.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: prompt }));
        }
        catch (_) {
            input.dispatchEvent(new Event("input", { bubbles: true, cancelable: true }));
        }
        input.dispatchEvent(new Event("change", { bubbles: true }));
    }

    async inject(input, prompt, options = {}) {
        const doc = input.ownerDocument, win = doc.defaultView;
        input.focus();
        const focusVerified = doc.activeElement === input || input.isContentEditable;
        if (options.forceFocus && !focusVerified)
            return { error: "Focus verification failed", code: "INPUT_VERIFICATION_FAILED" };
        if ("value" in input) {
            const proto = Object.getPrototypeOf(input), desc = Object.getOwnPropertyDescriptor(proto, "value");
            if (desc?.set)
                desc.set.call(input, prompt);
            else
                input.value = prompt;
            this.dispatchInputEvent(input, prompt);
            await new Promise(r => win.setTimeout(r, 50));
            const actual = String(input.value ?? "");
            if (actual !== prompt)
                return { error: "Input verification failed", code: "INPUT_VERIFICATION_FAILED" };
            return { input_method: "native_value_setter", input_verified: true, input_text_length: new TextEncoder().encode(actual).length, focus_verified: focusVerified, strategy: "provider_native_send" };
        }
        if (input.isContentEditable || input.getAttribute("contenteditable") === "true") {
            const sel = win.getSelection(), range = doc.createRange();
            range.selectNodeContents(input);
            sel.removeAllRanges();
            sel.addRange(range);
            let ok = false;
            try {
                ok = doc.execCommand("insertText", false, prompt);
            }
            catch (_) { }
            if (!ok)
                input.textContent = prompt;
            this.dispatchInputEvent(input, prompt);
            await new Promise(r => win.setTimeout(r, 50));
            const actual = String(input.textContent || "");
            if (actual !== prompt)
                return { error: "Contenteditable verification failed", code: "INPUT_VERIFICATION_FAILED" };
            return { input_method: "contenteditable", input_verified: true, input_text_length: new TextEncoder().encode(actual).length, focus_verified: focusVerified, strategy: "provider_native_send" };
        }
        return { error: "Unsupported input element", code: "INPUT_VERIFICATION_FAILED" };
    }

    async submitVerified(input, doc, options = {}) {
        let strategy = "provider_native_send";
        if (options.simulateEnter) {
            input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
            input.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
            strategy = "keyboard_enter";
        }
        else {
            const b = this.sendButton(doc);
            if (!b)
                return { error: "Provider send action unavailable", code: "SUBMISSION_FAILED" };
            b.focus();
            b.click();
        }
        const beforeCount = this.responseNodes(doc).length, before = "value" in input ? String(input.value || "") : String(input.textContent || ""), win = doc.defaultView, deadline = Date.now() + 5000;
        while (Date.now() < deadline) {
            if (this.isStreaming(doc) || this.responseNodes(doc).length > beforeCount)
                return { provider_submission_verified: true, submit_method: strategy === `keyboard_enter` ? `keyboard_enter` : `button_click`, strategy };
            const after = "value" in input ? String(input.value || "") : String(input.textContent || "");
            if (after !== before)
                return { provider_submission_verified: true, submit_method: strategy === `keyboard_enter` ? `keyboard_enter` : `button_click`, strategy };
            await new Promise(r => win.setTimeout(r, 100));
        }
        return { error: "Provider submission could not be positively verified", code: "SUBMISSION_FAILED" };
    }

    async verifyContinuationSubmission(doc) {
        const deadline = Date.now() + 5000, win = doc.defaultView;
        while (Date.now() < deadline) {
            if (this.isStreaming(doc))
                return true;
            await new Promise(r => win.setTimeout(r, 100));
        }
        return false;
    }

    cancel(doc) {
        const stop = this.findBySelectors(doc, ['button[aria-label*="Stop"]', 'button[data-testid*="stop"]', '[data-testid="stop-button"]']);
        if (!stop)
            return false;
        stop.click();
        return true;
    }

    inspect(doc) {
        const ns = this.responseNodes(doc), last = ns.length ? ns[ns.length - 1] : null;
        return { provider_context_valid: this.matchesDocument(doc), input_ready: !!this.input(doc), input_state: this.input(doc) ? "READY" : "NOT_READY", authenticated: this.isAuthenticated(doc), rate_limited: this.isRateLimited(doc), message_count: ns.length, last_message_text: String(last?.textContent || ""), streaming: this.isStreaming(doc), provider_state: this.isStreaming(doc) ? "busy" : "idle" };
    }
}
