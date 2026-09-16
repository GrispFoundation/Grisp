import { ProviderAdapter } from "./ProviderAdapter.sys.mjs";
import { garpDebug } from "../GarpDebug.sys.mjs";

function visible(element) {
    return !!element && !!(
        (element.offsetWidth > 0 ||
            element.offsetHeight > 0 ||
            element.getClientRects?.().length > 0) &&
        element.style?.display !== "none" &&
        element.style?.visibility !== "hidden"
    );
}

function enabled(element) {
    return !!element &&
        !element.disabled &&
        element.getAttribute("aria-disabled") !== "true" &&
        !element.classList?.contains("disabled") &&
        !element.classList?.contains("is-disabled") &&
        !element.classList?.contains("ds-button--disabled");
}

export class DeepSeekAdapter extends ProviderAdapter {
    constructor() {
        super("deepseek", "https://chat.deepseek.com/");
    }

    input(doc) {
        const selectors = [
            'textarea[placeholder="Message DeepSeek"]',
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

    async inject(input, prompt, options = {}) {
        const win = input?.ownerDocument?.defaultView;
        const targetPrompt = String(prompt ?? "");

        garpDebug(1, "DeepSeek inject begin", {
            prompt_length: targetPrompt.length,
            tag: input?.tagName || null,
            id: input?.id || null,
            classes: String(input?.className || ""),
        }, options.debugLevel);

        if (!input) {
            return {
                error: "DeepSeek input unavailable",
                code: "INPUT_VERIFICATION_FAILED",
            };
        }

        if (typeof input.focus === "function") {
            input.focus();
        }

        if ("value" in input) {
            if (typeof input.setSelectionRange === "function") {
                try {
                    input.setSelectionRange(0, String(input.value ?? "").length);
                } catch (_) {
                    // Some wrapped/native controls reject selection APIs.
                }
            }

            // DeepSeek's composer is framework-controlled. Setting the native
            // value property alone can be immediately overwritten by its
            // reactive state. execCommand(insertText) updates the editing
            // transaction in the same way the page's own composer does.
            for (let attempt = 1; attempt <= 3; attempt++) {
                try {
                    const doc = input.ownerDocument;
                    doc.execCommand("selectAll", false, null);
                    const inserted = doc.execCommand("insertText", false, targetPrompt);
                    input.dispatchEvent(new InputEvent("input", {
                        bubbles: true,
                        cancelable: true,
                        inputType: "insertText",
                        data: targetPrompt,
                    }));
                    input.dispatchEvent(new Event("change", {
                        bubbles: true,
                        cancelable: true,
                    }));

                    await new Promise(resolve => {
                        if (win) {
                            win.setTimeout(resolve, attempt === 1 ? 50 : 100);
                        } else {
                            setTimeout(resolve, attempt === 1 ? 50 : 100);
                        }
                    });

                    const actual = String(input.value ?? "");
                    garpDebug(2, "DeepSeek inject verification", {
                        attempt,
                        exec_command_inserted: !!inserted,
                        expected_length: targetPrompt.length,
                        actual_length: actual.length,
                        verified: actual === targetPrompt,
                    }, options.debugLevel);

                    if (actual === targetPrompt) {
                        return {
                            input_method: "exec_command_insert_text",
                            input_verified: true,
                            input_text_length: targetPrompt.length,
                            strategy: "provider_native_send",
                        };
                    }

                    // Re-focus before retrying in case the framework restored
                    // its value after processing the input event.
                    if (typeof input.focus === "function") {
                        input.focus();
                    }
                } catch (error) {
                    garpDebug(2, "DeepSeek execCommand injection attempt failed", {
                        attempt,
                        error: String(error?.message || error),
                    }, options.debugLevel);
                }
            }
        }

        garpDebug(1, "DeepSeek inject verification FAILED", {
            expected_length: targetPrompt.length,
            actual_length: String(input.value ?? input.textContent ?? "").length,
        }, options.debugLevel);

        return {
            error: "DeepSeek input verification failed",
            code: "INPUT_VERIFICATION_FAILED",
            details: {
                expected_input_length: targetPrompt.length,
                actual_input_length: String(input.value ?? input.textContent ?? "").length,
            },
        };
    }

    sendButton(doc) {
        const selectors = [
            ".bf38813a .ds-button--primary:not(.ds-button--disabled)",
            ".bf38813a [role=\"button\"].ds-button._52c986b",
            ".bf38813a .ds-icon-button._52c986b",
            ".bf38813a ._52c986b",
            '[role="button"].ds-button._52c986b',
            ".ds-button--primary:not(.ds-button--disabled)",
            'button[aria-label*="Send"]',
            '[data-testid*="send"]',
            'button[type="submit"]',
        ];

        for (const selector of selectors) {
            const matches = Array.from(doc.querySelectorAll(selector));
            for (let index = matches.length - 1; index >= 0; index--) {
                const result = matches[index];
                if (visible(result) && enabled(result)) {
                    garpDebug(2, "DeepSeek send button result", {
                        found: true,
                        selector,
                        tag: result.tagName || null,
                        id: result.id || null,
                        classes: String(result.className || ""),
                        text: String(result.textContent || "").trim().slice(0, 120),
                        aria_label: result.getAttribute?.("aria-label") || null,
                        title: result.getAttribute?.("title") || null,
                        data_testid: result.getAttribute?.("data-testid") || null,
                    });
                    return result;
                }
            }
        }

        garpDebug(2, "DeepSeek send button result", {
            found: false,
            selectors,
        });
        return null;
    }

    responseNodes(doc) {
        const selectors = [
            ".ds-message .ds-markdown",
            ".ds-markdown",
            ".ds-message-bubble",
        ];
        const result = this.findAllBySelectors(doc, selectors);
        garpDebug(2, "DeepSeek response nodes", {
            count: result.length,
            url: doc?.location?.href || "",
        });
        return result;
    }

    userMessageNodes(doc) {
        const selectors = [
            "._9663006",
            '[data-message-role="user"]',
            '[data-message-author-role="user"]',
            ".ds-user-message",
        ];
        const result = [];
        for (const selector of selectors) {
            result.push(...this.deepQuerySelectorAll(doc, selector));
        }
        return [...new Set(result)].filter(element => visible(element));
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

    async submitVerified(input, doc, options = {}) {
        if (!input || !doc) {
            return {
                error: "DeepSeek input/document unavailable",
                code: "SUBMISSION_FAILED",
            };
        }

        const win = doc.defaultView;
        const beforeResponseCount = this.responseNodes(doc).length;
        const beforeUserMessageCount = this.userMessageNodes(doc).length;
        const beforeInput = String(input.value ?? input.textContent ?? "");
        const beforeStreaming = this.isStreaming(doc);
        const button = this.sendButton(doc);

        garpDebug(1, "DeepSeek submission begin", {
            before_response_count: beforeResponseCount,
            before_user_message_count: beforeUserMessageCount,
            before_input_length: beforeInput.length,
            before_streaming: beforeStreaming,
            button_found: !!button,
            button_enabled: !!button && enabled(button),
        }, options.debugLevel);

        if (!button) {
            return {
                error: "DeepSeek send button not found",
                code: "SUBMISSION_FAILED",
                details: {
                    reason: "send_button_not_found",
                    before_input_length: beforeInput.length,
                },
            };
        }

        if (!enabled(button)) {
            return {
                error: "DeepSeek send button is disabled",
                code: "SUBMISSION_FAILED",
                details: {
                    reason: "send_button_disabled",
                    before_input_length: beforeInput.length,
                },
            };
        }

        button.focus();
        button.click();

        const deadline = Date.now() + 10000;
        while (Date.now() < deadline) {
            const currentResponseCount = this.responseNodes(doc).length;
            const currentUserMessageCount = this.userMessageNodes(doc).length;
            const currentInput = String(input.value ?? input.textContent ?? "");
            const currentStreaming = this.isStreaming(doc);
            const currentButton = this.sendButton(doc);

            const responseAppeared = currentResponseCount > beforeResponseCount;
            const userMessageAppeared = currentUserMessageCount > beforeUserMessageCount;
            const inputConsumed = beforeInput.length > 0 && currentInput.length === 0;
            const streamingStarted = !beforeStreaming && currentStreaming;
            const sendControlChanged =
                !currentButton ||
                currentButton !== button ||
                !enabled(currentButton);

            garpDebug(2, "DeepSeek submission verification", {
                response_count: currentResponseCount,
                user_message_count: currentUserMessageCount,
                input_length: currentInput.length,
                streaming: currentStreaming,
                response_appeared: responseAppeared,
                user_message_appeared: userMessageAppeared,
                input_consumed: inputConsumed,
                streaming_started: streamingStarted,
                send_control_changed: sendControlChanged,
            }, options.debugLevel);

            if (responseAppeared || userMessageAppeared || streamingStarted) {
                return {
                    provider_submission_verified: true,
                    submit_method: "button_click",
                    strategy: "provider_native_send",
                    verification: responseAppeared
                        ? "response_activity"
                        : userMessageAppeared
                            ? "user_message_activity"
                            : "streaming_started",
                };
            }

            if (inputConsumed && sendControlChanged) {
                return {
                    provider_submission_verified: true,
                    submit_method: "button_click",
                    strategy: "provider_native_send",
                    verification: "input_consumed_and_send_control_changed",
                };
            }

            await new Promise(resolve => win.setTimeout(resolve, 100));
        }

        const finalResponseCount = this.responseNodes(doc).length;
        const finalUserMessageCount = this.userMessageNodes(doc).length;
        const finalInput = String(input.value ?? input.textContent ?? "");
        const finalStreaming = this.isStreaming(doc);
        const finalButton = this.sendButton(doc);

        garpDebug(1, "DeepSeek submission verification FAILED", {
            final_response_count: finalResponseCount,
            final_user_message_count: finalUserMessageCount,
            final_input_length: finalInput.length,
            final_streaming: finalStreaming,
            final_button_found: !!finalButton,
            final_button_enabled: !!finalButton && enabled(finalButton),
        }, options.debugLevel);

        return {
            error: "DeepSeek provider submission could not be positively verified",
            code: "SUBMISSION_FAILED",
            details: {
                before_response_count: beforeResponseCount,
                final_response_count: finalResponseCount,
                before_user_message_count: beforeUserMessageCount,
                final_user_message_count: finalUserMessageCount,
                before_input_length: beforeInput.length,
                final_input_length: finalInput.length,
                final_streaming: finalStreaming,
                final_button_found: !!finalButton,
                final_button_enabled: !!finalButton && enabled(finalButton),
            },
        };
    }
}
