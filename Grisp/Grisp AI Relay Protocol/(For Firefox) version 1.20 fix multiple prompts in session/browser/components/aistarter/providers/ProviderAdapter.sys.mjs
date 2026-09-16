import { garpDebug } from "../GarpDebug.sys.mjs";
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
    matchesURL(url) {
        try {
            const expected = new URL(this.url);
            const actual = new URL(String(url || ""));
            return actual.protocol === expected.protocol &&
                (actual.hostname === expected.hostname || actual.hostname.endsWith(`.${expected.hostname}`));
        }
        catch (_) {
            return false;
        }
    }
    matchesDocument(doc) {
        return this.matchesURL(doc?.location?.href || "");
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
        garpDebug(2, "selector search begin", {
            provider: this.name,
            selectors: s,
            url: doc?.location?.href || "",
        });
        for (const sel of s)
            for (const e of this.deepQuerySelectorAll(doc, sel))
                if (this.visible(e) && this.enabled(e)) {
                    garpDebug(2, "selector match", {
                        provider: this.name,
                        selector: sel,
                        tag: e.tagName || null,
                        id: e.id || null,
                        classes: String(e.className || ""),
                    });
                    return e;
                }
        garpDebug(2, "selector search no match", {
            provider: this.name,
            selectors: s,
        });
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
        garpDebug(2, "adapter inject begin", {
            provider: this.name,
            tag: input?.tagName || null,
            id: input?.id || null,
            prompt_length: String(prompt ?? "").length,
            force_focus: !!options.forceFocus,
        }, options.debugLevel);
        const doc = input.ownerDocument, win = doc.defaultView;
        input.focus();
        const focusVerified = doc.activeElement === input || input.isContentEditable;
        garpDebug(2, "input focus verification", {
            provider: this.name,
            verified: focusVerified,
            active_tag: doc.activeElement?.tagName || null,
            active_id: doc.activeElement?.id || null,
        }, options.debugLevel);
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
            garpDebug(2, "native input verification", {
                provider: this.name,
                verified: actual === prompt,
                actual_length: actual.length,
            }, options.debugLevel);
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
            garpDebug(2, "contenteditable verification", {
                provider: this.name,
                verified: actual === prompt,
                actual_length: actual.length,
            }, options.debugLevel);
            if (actual !== prompt)
                return { error: "Contenteditable verification failed", code: "INPUT_VERIFICATION_FAILED" };
            return { input_method: "contenteditable", input_verified: true, input_text_length: new TextEncoder().encode(actual).length, focus_verified: focusVerified, strategy: "provider_native_send" };
        }
        return { error: "Unsupported input element", code: "INPUT_VERIFICATION_FAILED" };
    }
    async submitVerified(input, doc, options = {}) {
        garpDebug(2, "adapter submit begin", {
            provider: this.name,
            simulate_enter: !!options.simulateEnter,
            url: doc?.location?.href || "",
        }, options.debugLevel);

        const win = doc.defaultView;
        const beforeCount = this.responseNodes(doc).length;
        const before = "value" in input ? String(input.value || "") : String(input.textContent || "");
        const beforeStreaming = this.isStreaming(doc);
        let beforeButton = null;
        let buttonWasEnabled = false;
        let strategy = "provider_native_send";

        if (options.simulateEnter) {
            strategy = "keyboard_enter";
            garpDebug(2, "keyboard submit", {
                provider: this.name,
                before_message_count: beforeCount,
                before_input_length: before.length,
            }, options.debugLevel);
            input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
            input.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
        }
        else {
            beforeButton = this.sendButton(doc);
            buttonWasEnabled = !!beforeButton && this.enabled(beforeButton);
            garpDebug(2, "send action lookup BEFORE click", {
                provider: this.name,
                found: !!beforeButton,
                enabled: buttonWasEnabled,
                tag: beforeButton?.tagName || null,
                id: beforeButton?.id || null,
                classes: String(beforeButton?.className || ""),
                text: String(beforeButton?.textContent || "").trim().slice(0, 120),
                aria_label: beforeButton?.getAttribute?.("aria-label") || null,
                title: beforeButton?.getAttribute?.("title") || null,
                data_testid: beforeButton?.getAttribute?.("data-testid") || null,
            }, options.debugLevel);
            if (!beforeButton)
                return { error: "Provider send action unavailable", code: "SUBMISSION_FAILED", details: { reason: "send_button_not_found" } };
            if (!buttonWasEnabled)
                return { error: "Provider send action is disabled", code: "SUBMISSION_FAILED", details: { reason: "send_button_disabled" } };

            beforeButton.focus();
            garpDebug(2, "send action click", {
                provider: this.name,
                focused: doc.activeElement === beforeButton,
            }, options.debugLevel);
            beforeButton.click();
        }

        const deadline = Date.now() + 8000;
        garpDebug(1, "submission verification started", {
            provider: this.name,
            strategy,
            before_message_count: beforeCount,
            before_input_length: before.length,
            before_streaming: beforeStreaming,
            button_was_enabled: buttonWasEnabled,
        }, options.debugLevel);

        while (Date.now() < deadline) {
            const afterNodes = this.responseNodes(doc);
            const afterCount = afterNodes.length;
            const after = "value" in input ? String(input.value || "") : String(input.textContent || "");
            const afterStreaming = this.isStreaming(doc);
            const buttonAfter = strategy === "provider_native_send" ? this.sendButton(doc) : null;
            const buttonChanged = strategy === "provider_native_send" && (
                !buttonAfter ||
                !this.enabled(buttonAfter) ||
                buttonAfter !== beforeButton
            );
            const responseActivity = afterCount > beforeCount || (!beforeStreaming && afterStreaming);
            const inputConsumed = after !== before;

            if (responseActivity) {
                garpDebug(1, "submission verified by provider activity", {
                    provider: this.name,
                    strategy,
                    after_message_count: afterCount,
                    streaming: afterStreaming,
                }, options.debugLevel);
                return {
                    provider_submission_verified: true,
                    submit_method: strategy === "keyboard_enter" ? "keyboard_enter" : "button_click",
                    strategy,
                    verification: "provider_activity",
                };
            }

            if (strategy === "provider_native_send" && inputConsumed && buttonChanged) {
                garpDebug(1, "submission verified by input consumption and send-state change", {
                    provider: this.name,
                    strategy,
                    before_input_length: before.length,
                    after_input_length: after.length,
                    button_changed: buttonChanged,
                }, options.debugLevel);
                return {
                    provider_submission_verified: true,
                    submit_method: "button_click",
                    strategy,
                    verification: "input_consumed_and_button_state_changed",
                };
            }

            await new Promise(r => win.setTimeout(r, 100));
        }

        const finalNodes = this.responseNodes(doc);
        const finalInput = "value" in input ? String(input.value || "") : String(input.textContent || "");
        const finalButton = strategy === "provider_native_send" ? this.sendButton(doc) : null;
        garpDebug(1, "submission verification FAILED", {
            provider: this.name,
            strategy,
            final_message_count: finalNodes.length,
            final_input_length: finalInput.length,
            final_streaming: this.isStreaming(doc),
            final_button_found: !!finalButton,
            final_button_enabled: !!finalButton && this.enabled(finalButton),
        }, options.debugLevel);
        return {
            error: "Provider submission could not be positively verified",
            code: "SUBMISSION_FAILED",
            details: {
                before_message_count: beforeCount,
                final_message_count: finalNodes.length,
                before_input_length: before.length,
                final_input_length: finalInput.length,
                final_streaming: this.isStreaming(doc),
            },
        };
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

