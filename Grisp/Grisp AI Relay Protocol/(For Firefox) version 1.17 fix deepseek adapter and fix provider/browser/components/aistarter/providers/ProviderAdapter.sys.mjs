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

    matchesDocument(doc) {
        try {
            const expected = new URL(this.url);
            const actual = new URL(doc.location?.href || "");

            return actual.protocol === expected.protocol &&
                (
                    actual.hostname === expected.hostname ||
                    actual.hostname.endsWith(`.${expected.hostname}`)
                );
        }
        catch (_) {
            return false;
        }
    }

    deepQuerySelectorAll(doc, selector) {
        const result = Array.from(doc.querySelectorAll(selector));
        const roots = new Set();

        const walk = root => {
            if (!root || roots.has(root))
                return;

            roots.add(root);

            for (const element of root.querySelectorAll?.("*") || []) {
                if (element.shadowRoot) {
                    result.push(...element.shadowRoot.querySelectorAll(selector));
                    walk(element.shadowRoot);
                }
            }
        };

        walk(doc);

        return [...new Set(result)];
    }

    visible(element) {
        return !!element &&
            !!(
                element.offsetWidth > 0 ||
                element.offsetHeight > 0 ||
                element.getClientRects?.().length > 0
            ) &&
            element.style?.display !== "none" &&
            element.style?.visibility !== "hidden";
    }

    enabled(element) {
        return !!element &&
            !element.disabled &&
            element.getAttribute("aria-disabled") !== "true";
    }

    describeElement(element) {
        if (!element)
            return null;

        let rect = null;

        try {
            const r = element.getBoundingClientRect?.();

            if (r) {
                rect = {
                    x: Number(r.x),
                    y: Number(r.y),
                    width: Number(r.width),
                    height: Number(r.height),
                    top: Number(r.top),
                    right: Number(r.right),
                    bottom: Number(r.bottom),
                    left: Number(r.left),
                };
            }
        }
        catch (_) {
        }

        let value = null;

        try {
            if ("value" in element)
                value = String(element.value ?? "");
        }
        catch (_) {
        }

        return {
            tag: element.tagName || null,
            id: element.id || null,
            name: element.getAttribute?.("name") || null,
            type: element.getAttribute?.("type") || null,
            role: element.getAttribute?.("role") || null,
            aria_label: element.getAttribute?.("aria-label") || null,
            placeholder: element.getAttribute?.("placeholder") || null,
            class_name: String(element.className || ""),
            disabled: !!element.disabled,
            aria_disabled: element.getAttribute?.("aria-disabled") || null,
            read_only: !!element.readOnly,
            content_editable: element.getAttribute?.("contenteditable") || null,
            value_length: value === null ? null : value.length,
            value: value === null ? null : value.slice(0, 500),
            text_length: String(element.textContent || "").length,
            text: String(element.textContent || "").trim().slice(0, 500),
            outer_html: String(element.outerHTML || "").slice(0, 2000),
            visible: this.visible(element),
            enabled: this.enabled(element),
            rect,
        };
    }

    describeActiveElement(doc) {
        try {
            return this.describeElement(doc?.activeElement || null);
        }
        catch (_) {
            return null;
        }
    }

    getInputText(input) {
        if (!input)
            return "";

        try {
            if ("value" in input)
                return String(input.value ?? "");
        }
        catch (_) {
        }

        return String(input.textContent || "");
    }

    getInputState(input, doc) {
        return {
            input: this.describeElement(input),
            active_element: this.describeActiveElement(doc),
            active_element_is_input: doc?.activeElement === input,
            owner_document_url: input?.ownerDocument?.location?.href || "",
        };
    }

    getResponseState(doc) {
        try {
            const nodes = this.responseNodes(doc);
            const messages = nodes.map((node, index) => ({
                index,
                text_length: String(node.textContent || "").length,
                text: String(node.textContent || "").slice(0, 1000),
                element: this.describeElement(node),
            }));

            return {
                count: nodes.length,
                messages,
            };
        }
        catch (error) {
            return {
                count: 0,
                error: error?.message || String(error),
                messages: [],
            };
        }
    }

    getStreamingState(doc) {
        try {
            return {
                streaming: !!this.isStreaming(doc),
                url: doc?.location?.href || "",
            };
        }
        catch (error) {
            return {
                streaming: false,
                error: error?.message || String(error),
                url: doc?.location?.href || "",
            };
        }
    }

    logInjectionState(stage, input, doc, extra = {}, debugLevel = 2) {
        garpDebug(2, `INJECTION DEBUG ${stage}`, {
            provider: this.name,
            stage,
            timestamp_ms: Date.now(),
            url: doc?.location?.href || "",
            input_state: this.getInputState(input, doc),
            response_state: this.getResponseState(doc),
            streaming_state: this.getStreamingState(doc),
            ...extra,
        }, debugLevel);
    }

    findBySelectors(doc, selectors) {
        garpDebug(2, "selector search begin", {
            provider: this.name,
            selectors,
            url: doc?.location?.href || "",
        });

        for (const selector of selectors) {
            const elements = this.deepQuerySelectorAll(doc, selector);

            garpDebug(3, "selector candidates", {
                provider: this.name,
                selector,
                candidate_count: elements.length,
            });

            for (const element of elements) {
                const visible = this.visible(element);
                const enabled = this.enabled(element);

                garpDebug(3, "selector candidate", {
                    provider: this.name,
                    selector,
                    visible,
                    enabled,
                    element: this.describeElement(element),
                });

                if (visible && enabled) {
                    garpDebug(2, "selector match", {
                        provider: this.name,
                        selector,
                        element: this.describeElement(element),
                    });

                    return element;
                }
            }
        }

        garpDebug(2, "selector search no match", {
            provider: this.name,
            selectors,
        });

        return null;
    }

    findAllBySelectors(doc, selectors) {
        const result = [];

        for (const selector of selectors) {
            const elements = this.deepQuerySelectorAll(doc, selector);

            garpDebug(3, "selector all candidates", {
                provider: this.name,
                selector,
                count: elements.length,
            });

            result.push(...elements);
        }

        return [...new Set(result)].filter(element => this.visible(element));
    }

    findContinueButton(doc) {
        const selectors = [
            'button[data-testid*="continue"]',
            'button[aria-label*="Continue"]',
            'button[aria-label*="continue"]',
            "button",
            "[role=button]",
        ];

        const isContinueText = text => {
            const value = String(text || "").trim().toLowerCase();

            return value === "continue" ||
                value.startsWith("continue") ||
                value === "继续" ||
                value.includes("继续生成") ||
                value === "continuer" ||
                value === "continuar" ||
                value === "weiter";
        };

        for (const element of this.findAllBySelectors(doc, selectors).reverse()) {
            if (
                isContinueText(element.textContent) ||
                isContinueText(element.getAttribute("aria-label"))
            ) {
                return element;
            }
        }

        return null;
    }

    input(doc) {
        return this.findBySelectors(doc, [
            "textarea",
            '[contenteditable="true"]',
        ]);
    }

    sendButton(doc) {
        return this.findBySelectors(doc, [
            'button[aria-label*="Send"]',
            'button[aria-label*="Submit"]',
            'button[type="submit"]',
            '[data-testid*="send"]',
        ]);
    }

    responseNodes(doc) {
        return this.findAllBySelectors(doc, [
            ".markdown",
            '[data-message-author-role="assistant"]',
        ]);
    }

    isStreaming(doc) {
        return !!doc.querySelector(
            '[data-streaming="true"],' +
            '.loading-indicator,' +
            '.spinner,' +
            'button[aria-label*="Stop"],' +
            '[data-testid*="stop"]'
        );
    }

    isAuthenticated(_doc) {
        return true;
    }

    isRateLimited(_doc) {
        return false;
    }

    dispatchInputEvent(input, prompt, debugLevel = 2) {
        const doc = input.ownerDocument;

        garpDebug(2, "INJECTION DEBUG dispatch input event BEGIN", {
            provider: this.name,
            input: this.describeElement(input),
            prompt_length: String(prompt ?? "").length,
            prompt_preview: String(prompt ?? "").slice(0, 500),
        }, debugLevel);

        try {
            const event = new InputEvent(
                "input",
                {
                    bubbles: true,
                    cancelable: true,
                    inputType: "insertText",
                    data: prompt,
                }
            );

            const dispatched = input.dispatchEvent(event);

            garpDebug(2, "INJECTION DEBUG input event dispatched", {
                provider: this.name,
                event_type: event.type,
                input_type: event.inputType,
                data_length: String(event.data ?? "").length,
                bubbles: event.bubbles,
                cancelable: event.cancelable,
                default_prevented: event.defaultPrevented,
                dispatch_returned: dispatched,
            }, debugLevel);
        }
        catch (error) {
            garpDebug(1, "INJECTION DEBUG InputEvent failed, fallback Event", {
                provider: this.name,
                error: error?.message || String(error),
            }, debugLevel);

            const event = new Event(
                "input",
                {
                    bubbles: true,
                    cancelable: true,
                }
            );

            const dispatched = input.dispatchEvent(event);

            garpDebug(2, "INJECTION DEBUG fallback input event dispatched", {
                provider: this.name,
                event_type: event.type,
                bubbles: event.bubbles,
                cancelable: event.cancelable,
                default_prevented: event.defaultPrevented,
                dispatch_returned: dispatched,
            }, debugLevel);
        }

        garpDebug(2, "INJECTION DEBUG dispatch change event BEGIN", {
            provider: this.name,
            input: this.describeElement(input),
        }, debugLevel);

        try {
            const event = new Event(
                "change",
                {
                    bubbles: true,
                    cancelable: true,
                }
            );

            const dispatched = input.dispatchEvent(event);

            garpDebug(2, "INJECTION DEBUG change event dispatched", {
                provider: this.name,
                event_type: event.type,
                bubbles: event.bubbles,
                cancelable: event.cancelable,
                default_prevented: event.defaultPrevented,
                dispatch_returned: dispatched,
            }, debugLevel);
        }
        catch (error) {
            garpDebug(1, "INJECTION DEBUG change event failed", {
                provider: this.name,
                error: error?.message || String(error),
            }, debugLevel);
        }

        garpDebug(2, "INJECTION DEBUG dispatch events END", {
            provider: this.name,
            resulting_input_state: this.describeElement(input),
            active_element: this.describeActiveElement(doc),
        }, debugLevel);
    }

    async inject(input, prompt, options = {}) {
        const debugLevel = options.debugLevel ?? 2;
        const normalizedPrompt = String(prompt ?? "");
        const doc = input?.ownerDocument;
        const win = doc?.defaultView;

        garpDebug(1, "INJECTION DEBUG ==================== BEGIN ====================", {
            provider: this.name,
            prompt_length: normalizedPrompt.length,
            prompt_preview: normalizedPrompt.slice(0, 1000),
            force_focus: !!options.forceFocus,
            url: doc?.location?.href || "",
        }, debugLevel);

        if (!input || !doc || !win) {
            garpDebug(1, "INJECTION DEBUG INVALID INPUT CONTEXT", {
                provider: this.name,
                has_input: !!input,
                has_document: !!doc,
                has_window: !!win,
            }, debugLevel);

            return {
                error: "Invalid input/document context",
                code: "INPUT_VERIFICATION_FAILED",
            };
        }

        this.logInjectionState(
            "BEFORE_FOCUS",
            input,
            doc,
            {
                prompt_length: normalizedPrompt.length,
                existing_value: this.getInputText(input),
            },
            debugLevel
        );

        try {
            input.focus();
        }
        catch (error) {
            garpDebug(1, "INJECTION DEBUG input.focus() threw", {
                provider: this.name,
                error: error?.message || String(error),
            }, debugLevel);
        }

        const focusVerified =
            doc.activeElement === input ||
            input.isContentEditable;

        this.logInjectionState(
            "AFTER_FOCUS",
            input,
            doc,
            {
                focus_verified: focusVerified,
                active_element_is_input: doc.activeElement === input,
            },
            debugLevel
        );

        if (options.forceFocus && !focusVerified) {
            garpDebug(1, "INJECTION DEBUG FOCUS VERIFICATION FAILED", {
                provider: this.name,
                focus_verified: focusVerified,
                active_element: this.describeActiveElement(doc),
                input: this.describeElement(input),
            }, debugLevel);

            return {
                error: "Focus verification failed",
                code: "INPUT_VERIFICATION_FAILED",
            };
        }

        if (!normalizedPrompt) {
            garpDebug(1, "INJECTION DEBUG EMPTY PROMPT", {
                provider: this.name,
            }, debugLevel);

            return {
                error: "Prompt is empty",
                code: "INVALID_ARGUMENT",
            };
        }

        if ("value" in input) {
            const previousValue = this.getInputText(input);
            const prototype = Object.getPrototypeOf(input);

            let descriptor = null;

            try {
                descriptor = Object.getOwnPropertyDescriptor(
                    prototype,
                    "value"
                );
            }
            catch (error) {
                garpDebug(1, "INJECTION DEBUG value descriptor lookup failed", {
                    provider: this.name,
                    error: error?.message || String(error),
                }, debugLevel);
            }

            garpDebug(2, "INJECTION DEBUG VALUE SETTER INSPECTION", {
                provider: this.name,
                input: this.describeElement(input),
                prototype_name: prototype?.constructor?.name || null,
                descriptor_exists: !!descriptor,
                descriptor_has_getter: !!descriptor?.get,
                descriptor_has_setter: !!descriptor?.set,
                descriptor_enumerable: descriptor?.enumerable ?? null,
                descriptor_configurable: descriptor?.configurable ?? null,
                previous_value_length: previousValue.length,
                previous_value_preview: previousValue.slice(0, 500),
            }, debugLevel);

            let setterUsed = false;
            let setterError = null;

            try {
                if (descriptor?.set) {
                    garpDebug(2, "INJECTION DEBUG CALLING PROTOTYPE VALUE SETTER", {
                        provider: this.name,
                        setter_function: String(descriptor.set).slice(0, 1000),
                    }, debugLevel);

                    descriptor.set.call(input, normalizedPrompt);
                    setterUsed = true;

                    garpDebug(2, "INJECTION DEBUG PROTOTYPE VALUE SETTER COMPLETED", {
                        provider: this.name,
                    }, debugLevel);
                }
                else {
                    garpDebug(2, "INJECTION DEBUG NO PROTOTYPE SETTER; USING input.value =", {
                        provider: this.name,
                    }, debugLevel);

                    input.value = normalizedPrompt;
                    setterUsed = false;
                }
            }
            catch (error) {
                setterError = error;

                garpDebug(1, "INJECTION DEBUG VALUE SETTER THREW", {
                    provider: this.name,
                    error: error?.message || String(error),
                    name: error?.name || null,
                    stack: error?.stack || null,
                }, debugLevel);

                return {
                    error: "Input value injection threw an exception",
                    code: "INPUT_VERIFICATION_FAILED",
                    details: error?.message || String(error),
                };
            }

            const afterSetter = this.getInputText(input);

            this.logInjectionState(
                "AFTER_VALUE_SETTER",
                input,
                doc,
                {
                    setter_used: setterUsed,
                    setter_error: setterError?.message || null,
                    previous_value_length: previousValue.length,
                    after_setter_length: afterSetter.length,
                    expected_length: normalizedPrompt.length,
                    exact_match: afterSetter === normalizedPrompt,
                    expected_preview: normalizedPrompt.slice(0, 500),
                    actual_preview: afterSetter.slice(0, 500),
                },
                debugLevel
            );

            if (afterSetter !== normalizedPrompt) {
                garpDebug(1, "INJECTION DEBUG VALUE MISMATCH IMMEDIATELY AFTER SETTER", {
                    provider: this.name,
                    expected_length: normalizedPrompt.length,
                    actual_length: afterSetter.length,
                    expected: normalizedPrompt.slice(0, 1000),
                    actual: afterSetter.slice(0, 1000),
                    input: this.describeElement(input),
                }, debugLevel);

                return {
                    error: "Input verification failed immediately after value setter",
                    code: "INPUT_VERIFICATION_FAILED",
                };
            }

            this.dispatchInputEvent(
                input,
                normalizedPrompt,
                debugLevel
            );

            this.logInjectionState(
                "AFTER_INPUT_CHANGE_EVENTS",
                input,
                doc,
                {
                    expected_length: normalizedPrompt.length,
                    exact_match: this.getInputText(input) === normalizedPrompt,
                },
                debugLevel
            );

            const verificationDelays = [
                10,
                50,
                100,
                250,
            ];

            for (const delay of verificationDelays) {
                await new Promise(resolve => win.setTimeout(resolve, delay));

                const actual = this.getInputText(input);

                this.logInjectionState(
                    `POST_INPUT_VERIFY_${delay}MS`,
                    input,
                    doc,
                    {
                        verification_delay_ms: delay,
                        expected_length: normalizedPrompt.length,
                        actual_length: actual.length,
                        exact_match: actual === normalizedPrompt,
                        actual_preview: actual.slice(0, 500),
                    },
                    debugLevel
                );

                if (actual !== normalizedPrompt) {
                    garpDebug(1, "INJECTION DEBUG VALUE CHANGED BEFORE SUBMIT", {
                        provider: this.name,
                        delay_ms: delay,
                        expected_length: normalizedPrompt.length,
                        actual_length: actual.length,
                        expected: normalizedPrompt.slice(0, 1000),
                        actual: actual.slice(0, 1000),
                        active_element: this.describeActiveElement(doc),
                    }, debugLevel);

                    return {
                        error: "Input value changed before submission",
                        code: "INPUT_VERIFICATION_FAILED",
                    };
                }
            }

            garpDebug(1, "INJECTION DEBUG INPUT INJECTION VERIFIED", {
                provider: this.name,
                setter_used: setterUsed,
                value_length: normalizedPrompt.length,
                focus_verified: doc.activeElement === input || input.isContentEditable,
            }, debugLevel);

            return {
                input_method: "native_value_setter",
                input_verified: true,
                input_text_length: new TextEncoder().encode(normalizedPrompt).length,
                focus_verified: doc.activeElement === input || input.isContentEditable,
                setter_used: setterUsed,
                strategy: "provider_native_send",
            };
        }

        if (
            input.isContentEditable ||
            input.getAttribute("contenteditable") === "true"
        ) {
            garpDebug(2, "INJECTION DEBUG CONTENTEDITABLE PATH", {
                provider: this.name,
                input: this.describeElement(input),
            }, debugLevel);

            const selection = win.getSelection();
            const range = doc.createRange();

            try {
                range.selectNodeContents(input);
                selection.removeAllRanges();
                selection.addRange(range);

                garpDebug(2, "INJECTION DEBUG CONTENTEDITABLE SELECTION CREATED", {
                    provider: this.name,
                    selection_text: String(selection?.toString?.() || "").slice(0, 500),
                }, debugLevel);
            }
            catch (error) {
                garpDebug(1, "INJECTION DEBUG CONTENTEDITABLE SELECTION FAILED", {
                    provider: this.name,
                    error: error?.message || String(error),
                }, debugLevel);
            }

            let execCommandResult = false;

            try {
                execCommandResult = doc.execCommand(
                    "insertText",
                    false,
                    normalizedPrompt
                );

                garpDebug(2, "INJECTION DEBUG execCommand(insertText)", {
                    provider: this.name,
                    result: execCommandResult,
                }, debugLevel);
            }
            catch (error) {
                garpDebug(1, "INJECTION DEBUG execCommand(insertText) THREW", {
                    provider: this.name,
                    error: error?.message || String(error),
                }, debugLevel);
            }

            if (!execCommandResult) {
                garpDebug(2, "INJECTION DEBUG CONTENTEDITABLE FALLBACK textContent =", {
                    provider: this.name,
                }, debugLevel);

                input.textContent = normalizedPrompt;
            }

            this.dispatchInputEvent(
                input,
                normalizedPrompt,
                debugLevel
            );

            await new Promise(resolve => win.setTimeout(resolve, 50));

            const actual = String(input.textContent || "");

            this.logInjectionState(
                "CONTENTEDITABLE_VERIFY",
                input,
                doc,
                {
                    exec_command_result: execCommandResult,
                    expected_length: normalizedPrompt.length,
                    actual_length: actual.length,
                    exact_match: actual === normalizedPrompt,
                    actual_preview: actual.slice(0, 1000),
                },
                debugLevel
            );

            if (actual !== normalizedPrompt) {
                return {
                    error: "Contenteditable verification failed",
                    code: "INPUT_VERIFICATION_FAILED",
                };
            }

            return {
                input_method: "contenteditable",
                input_verified: true,
                input_text_length: new TextEncoder().encode(actual).length,
                focus_verified: doc.activeElement === input || input.isContentEditable,
                strategy: "provider_native_send",
            };
        }

        garpDebug(1, "INJECTION DEBUG UNSUPPORTED INPUT ELEMENT", {
            provider: this.name,
            input: this.describeElement(input),
        }, debugLevel);

        return {
            error: "Unsupported input element",
            code: "INPUT_VERIFICATION_FAILED",
        };
    }

    async submitVerified(input, doc, options = {}) {
        const debugLevel = options.debugLevel ?? 2;
        const simulateEnter = !!options.simulateEnter;

        const beforeInputText = this.getInputText(input);
        const beforeUrl = doc.location?.href || "";
        const beforeResponses = this.getResponseState(doc);
        const beforeStreaming = this.getStreamingState(doc);

        garpDebug(1, "SUBMISSION DEBUG ==================== BEGIN ====================", {
            provider: this.name,
            simulate_enter: simulateEnter,
            url_before: beforeUrl,
            input_before: this.describeElement(input),
            input_text_before: beforeInputText.slice(0, 1000),
            input_text_before_length: beforeInputText.length,
            response_before: beforeResponses,
            streaming_before: beforeStreaming,
        }, debugLevel);

        if (simulateEnter) {
            garpDebug(1, "SUBMISSION DEBUG DISPATCHING ENTER", {
                provider: this.name,
                input: this.describeElement(input),
            }, debugLevel);

            let keydownEvent = null;
            let keyupEvent = null;

            try {
                keydownEvent = new KeyboardEvent(
                    "keydown",
                    {
                        key: "Enter",
                        code: "Enter",
                        bubbles: true,
                        cancelable: true,
                    }
                );

                const dispatched = input.dispatchEvent(keydownEvent);

                garpDebug(2, "SUBMISSION DEBUG keydown dispatched", {
                    provider: this.name,
                    dispatched,
                    default_prevented: keydownEvent.defaultPrevented,
                }, debugLevel);
            }
            catch (error) {
                garpDebug(1, "SUBMISSION DEBUG keydown threw", {
                    provider: this.name,
                    error: error?.message || String(error),
                }, debugLevel);
            }

            try {
                keyupEvent = new KeyboardEvent(
                    "keyup",
                    {
                        key: "Enter",
                        code: "Enter",
                        bubbles: true,
                        cancelable: true,
                    }
                );

                const dispatched = input.dispatchEvent(keyupEvent);

                garpDebug(2, "SUBMISSION DEBUG keyup dispatched", {
                    provider: this.name,
                    dispatched,
                    default_prevented: keyupEvent.defaultPrevented,
                }, debugLevel);
            }
            catch (error) {
                garpDebug(1, "SUBMISSION DEBUG keyup threw", {
                    provider: this.name,
                    error: error?.message || String(error),
                }, debugLevel);
            }
        }
        else {
            const button = this.sendButton(doc);

            garpDebug(1, "SUBMISSION DEBUG SEND BUTTON LOOKUP", {
                provider: this.name,
                found: !!button,
                button: this.describeElement(button),
                all_visible_buttons: this.findAllBySelectors(doc, [
                    "button",
                    '[role="button"]',
                ]).slice(-20).map(element => this.describeElement(element)),
            }, debugLevel);

            if (!button) {
                garpDebug(1, "SUBMISSION DEBUG SEND BUTTON NOT FOUND", {
                    provider: this.name,
                }, debugLevel);

                return {
                    error: "Provider send action unavailable",
                    code: "SUBMISSION_FAILED",
                };
            }

            try {
                button.focus();

                garpDebug(2, "SUBMISSION DEBUG BUTTON FOCUS RESULT", {
                    provider: this.name,
                    focused: doc.activeElement === button,
                    active_element: this.describeActiveElement(doc),
                    button: this.describeElement(button),
                }, debugLevel);
            }
            catch (error) {
                garpDebug(1, "SUBMISSION DEBUG BUTTON FOCUS THREW", {
                    provider: this.name,
                    error: error?.message || String(error),
                }, debugLevel);
            }

            this.logInjectionState(
                "IMMEDIATELY_BEFORE_BUTTON_CLICK",
                input,
                doc,
                {
                    button: this.describeElement(button),
                    active_element: this.describeActiveElement(doc),
                    url: doc.location?.href || "",
                },
                debugLevel
            );

            garpDebug(1, "SUBMISSION DEBUG CALLING button.click()", {
                provider: this.name,
                button: this.describeElement(button),
            }, debugLevel);

            try {
                button.click();

                garpDebug(1, "SUBMISSION DEBUG button.click() RETURNED", {
                    provider: this.name,
                    url_after_click_return: doc.location?.href || "",
                    active_element_after_click: this.describeActiveElement(doc),
                    input_after_click: this.describeElement(input),
                }, debugLevel);
            }
            catch (error) {
                garpDebug(1, "SUBMISSION DEBUG button.click() THREW", {
                    provider: this.name,
                    error: error?.message || String(error),
                    stack: error?.stack || null,
                }, debugLevel);

                return {
                    error: "Provider send action threw an exception",
                    code: "SUBMISSION_FAILED",
                    details: error?.message || String(error),
                };
            }
        }

        const observationDelays = [
            25,
            100,
            250,
            500,
            1000,
            2000,
        ];

        let activityObserved = false;
        let activityReasons = [];

        for (const delay of observationDelays) {
            await new Promise(resolve => doc.defaultView.setTimeout(resolve, delay));

            const currentInputText = this.getInputText(input);
            const currentUrl = doc.location?.href || "";
            const currentResponses = this.getResponseState(doc);
            const currentStreaming = this.getStreamingState(doc);

            const urlChanged = currentUrl !== beforeUrl;
            const responseCountChanged =
                currentResponses.count !== beforeResponses.count;

            const responseTextChanged =
                currentResponses.messages.some(
                    (message, index) =>
                        message.text !==
                        (beforeResponses.messages[index]?.text || "")
                );

            const streamingStarted =
                currentStreaming.streaming &&
                !beforeStreaming.streaming;

            const inputChanged =
                currentInputText !== beforeInputText;

            const inputCleared =
                beforeInputText.length > 0 &&
                currentInputText.length === 0;

            const meaningfulProviderActivity =
                urlChanged ||
                responseCountChanged ||
                responseTextChanged ||
                currentStreaming.streaming;

            if (meaningfulProviderActivity)
                activityObserved = true;

            if (urlChanged && !activityReasons.includes("url_changed"))
                activityReasons.push("url_changed");

            if (responseCountChanged && !activityReasons.includes("response_count_changed"))
                activityReasons.push("response_count_changed");

            if (responseTextChanged && !activityReasons.includes("response_text_changed"))
                activityReasons.push("response_text_changed");

            if (streamingStarted && !activityReasons.includes("streaming_started"))
                activityReasons.push("streaming_started");

            this.logInjectionState(
                `POST_SUBMIT_OBSERVATION_${delay}MS`,
                input,
                doc,
                {
                    observation_delay_ms: delay,
                    url_before: beforeUrl,
                    url_current: currentUrl,
                    url_changed: urlChanged,
                    input_before_length: beforeInputText.length,
                    input_current_length: currentInputText.length,
                    input_changed: inputChanged,
                    input_cleared: inputCleared,
                    response_count_before: beforeResponses.count,
                    response_count_current: currentResponses.count,
                    response_count_changed: responseCountChanged,
                    response_text_changed: responseTextChanged,
                    streaming_before: beforeStreaming.streaming,
                    streaming_current: currentStreaming.streaming,
                    streaming_started: streamingStarted,
                    meaningful_provider_activity: meaningfulProviderActivity,
                    activity_observed_so_far: activityObserved,
                    activity_reasons: [...activityReasons],
                },
                debugLevel
            );
        }

        const finalInputText = this.getInputText(input);
        const finalUrl = doc.location?.href || "";
        const finalResponses = this.getResponseState(doc);
        const finalStreaming = this.getStreamingState(doc);

        const finalUrlChanged = finalUrl !== beforeUrl;
        const finalResponseCountChanged =
            finalResponses.count !== beforeResponses.count;

        const finalResponseTextChanged =
            finalResponses.messages.some(
                (message, index) =>
                    message.text !==
                    (beforeResponses.messages[index]?.text || "")
            );

        const finalProviderActivity =
            finalUrlChanged ||
            finalResponseCountChanged ||
            finalResponseTextChanged ||
            finalStreaming.streaming;

        garpDebug(1, "SUBMISSION DEBUG FINAL CLASSIFICATION", {
            provider: this.name,
            url_before: beforeUrl,
            url_after: finalUrl,
            url_changed: finalUrlChanged,
            input_before_length: beforeInputText.length,
            input_after_length: finalInputText.length,
            input_changed: finalInputText !== beforeInputText,
            input_cleared:
                beforeInputText.length > 0 &&
                finalInputText.length === 0,
            response_count_before: beforeResponses.count,
            response_count_after: finalResponses.count,
            response_count_changed: finalResponseCountChanged,
            response_text_changed: finalResponseTextChanged,
            streaming_before: beforeStreaming.streaming,
            streaming_after: finalStreaming.streaming,
            provider_activity_detected: finalProviderActivity,
            activity_observed_during_window: activityObserved,
            activity_reasons: activityReasons,
            final_input: this.describeElement(input),
            final_responses: finalResponses,
        }, debugLevel);

        /*
         * IMPORTANT:
         *
         * A changed or cleared textarea is NOT authoritative proof of
         * provider submission.  We deliberately do not use:
         *
         *     finalInputText !== beforeInputText
         *
         * as submission evidence.
         *
         * The only evidence accepted here is actual provider-side activity:
         *
         *     - navigation
         *     - response node appeared/changed
         *     - streaming became active
         */
        if (!finalProviderActivity) {
            garpDebug(1, "SUBMISSION DEBUG FAILED: NO PROVIDER ACTIVITY", {
                provider: this.name,
                url: finalUrl,
                input_changed: finalInputText !== beforeInputText,
                input_cleared:
                    beforeInputText.length > 0 &&
                    finalInputText.length === 0,
                response_count: finalResponses.count,
                streaming: finalStreaming.streaming,
                activity_reasons: activityReasons,
            }, debugLevel);

            garpDebug(1, "SUBMISSION DEBUG ===================== END: FAILED =====================", {
                provider: this.name,
            }, debugLevel);

            return {
                error: "Provider submission could not be positively verified",
                code: "SUBMISSION_FAILED",
                diagnostics: {
                    url_changed: finalUrlChanged,
                    response_count_changed: finalResponseCountChanged,
                    response_text_changed: finalResponseTextChanged,
                    streaming: finalStreaming.streaming,
                    input_changed: finalInputText !== beforeInputText,
                    input_cleared:
                        beforeInputText.length > 0 &&
                        finalInputText.length === 0,
                    activity_reasons: [...activityReasons],
                },
            };
        }

        const strategy = simulateEnter
            ? "keyboard_enter"
            : "provider_native_send";

        garpDebug(1, "SUBMISSION DEBUG VERIFIED PROVIDER ACTIVITY", {
            provider: this.name,
            strategy,
            submit_method: simulateEnter ? "keyboard_enter" : "button_click",
            activity_reasons: activityReasons,
            final_url: finalUrl,
            final_response_count: finalResponses.count,
            final_streaming: finalStreaming.streaming,
        }, debugLevel);

        garpDebug(1, "SUBMISSION DEBUG ===================== END: VERIFIED =====================", {
            provider: this.name,
        }, debugLevel);

        return {
            provider_submission_verified: true,
            submit_method: simulateEnter
                ? "keyboard_enter"
                : "button_click",
            strategy,
            provider_activity_detected: true,
            provider_activity_reasons: [...activityReasons],
        };
    }

    async verifyContinuationSubmission(doc) {
        const deadline = Date.now() + 5000;
        const win = doc.defaultView;

        while (Date.now() < deadline) {
            if (this.isStreaming(doc))
                return true;

            await new Promise(resolve => win.setTimeout(resolve, 100));
        }

        return false;
    }

    cancel(doc) {
        const stop = this.findBySelectors(
            doc,
            [
                'button[aria-label*="Stop"]',
                'button[data-testid*="stop"]',
                '[data-testid="stop-button"]',
            ]
        );

        if (!stop)
            return false;

        stop.click();
        return true;
    }

    inspect(doc) {
        const nodes = this.responseNodes(doc);
        const last = nodes.length
            ? nodes[nodes.length - 1]
            : null;

        return {
            provider_context_valid: this.matchesDocument(doc),
            input_ready: !!this.input(doc),
            input_state: this.input(doc)
                ? "READY"
                : "NOT_READY",
            authenticated: this.isAuthenticated(doc),
            rate_limited: this.isRateLimited(doc),
            message_count: nodes.length,
            last_message_text: String(last?.textContent || ""),
            streaming: this.isStreaming(doc),
            provider_state: this.isStreaming(doc)
                ? "busy"
                : "idle",
        };
    }
}