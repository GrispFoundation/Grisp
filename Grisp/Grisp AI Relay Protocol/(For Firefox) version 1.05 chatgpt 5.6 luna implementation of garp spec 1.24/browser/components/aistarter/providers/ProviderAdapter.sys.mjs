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

  supportsContinuation(_doc) { return true; }

  matchesDocument(doc) {
    try {
      const expected = new URL(this.url);
      const actual = new URL(doc.location?.href || "");
      return actual.protocol === expected.protocol && (actual.hostname === expected.hostname || actual.hostname.endsWith(`.${expected.hostname}`));
    } catch (_) {
      return false;
    }
  }

  deepQuerySelectorAll(doc, selector) {
    const results = Array.from(doc.querySelectorAll(selector));
    const seenRoots = new Set();
    const walk = root => {
      if (!root || seenRoots.has(root)) return;
      seenRoots.add(root);
      for (const element of root.querySelectorAll?.("*") || []) {
        if (element.shadowRoot) {
          results.push(...element.shadowRoot.querySelectorAll(selector));
          walk(element.shadowRoot);
        }
      }
    };
    walk(doc);
    return [...new Set(results)];
  }

  visible(element) {
    if (!element) return false;
    return !!((element.offsetWidth > 0 || element.offsetHeight > 0 || element.getClientRects?.().length > 0) && element.style?.display !== "none" && element.style?.visibility !== "hidden");
  }

  enabled(element) { return !!element && !element.disabled && element.getAttribute("aria-disabled") !== "true"; }

  findBySelectors(doc, selectors) {
    for (const selector of selectors) for (const element of this.deepQuerySelectorAll(doc, selector)) if (this.visible(element) && this.enabled(element)) return element;
    return null;
  }

  findAllBySelectors(doc, selectors) {
    const result = [];
    for (const selector of selectors) result.push(...this.deepQuerySelectorAll(doc, selector));
    return [...new Set(result)].filter(element => this.visible(element));
  }

  findContinueButton(doc) {
    const selectors = ['button[data-testid*="continue"]', 'button[aria-label*="Continue"]', 'button[aria-label*="continue"]', 'button[aria-label*="继续"]', "button", "[role=button]"];
    const isContinue = text => {
      const value = String(text || "").trim().toLowerCase();
      return value === "continue" || value.startsWith("continue") || value === "继续" || value.includes("继续生成") || value === "continuer" || value === "continuar" || value === "weiter";
    };
    for (const element of this.findAllBySelectors(doc, selectors).reverse()) if (isContinue(element.textContent) || isContinue(element.getAttribute("aria-label"))) return element;
    return null;
  }

  input(doc) { return this.findBySelectors(doc, ["textarea", '[contenteditable="true"]']); }
  sendButton(doc) { return this.findBySelectors(doc, ['button[aria-label*="Send"]', 'button[aria-label*="Submit"]', 'button[type="submit"]', '[data-testid*="send"]']); }
  responseNodes(doc) { return this.findAllBySelectors(doc, [".markdown", '[data-message-author-role="assistant"]']); }
  isStreaming(doc) { return !!doc.querySelector('[data-streaming="true"], .loading-indicator, .spinner, button[aria-label*="Stop"], [data-testid*="stop"]'); }
  isAuthenticated(_doc) { return true; }
  isRateLimited(_doc) { return false; }

  dispatchInputEvent(input, prompt) {
    const win = input.ownerDocument.defaultView;
    try {
      input.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: prompt }));
    } catch (_) {
      input.dispatchEvent(new Event("input", { bubbles: true, cancelable: true }));
    }
    input.dispatchEvent(new Event("change", { bubbles: true }));
    return win;
  }

  async inject(input, prompt, options = {}) {
    if (!input) throw Object.assign(new Error("Input element is unavailable"), { code: "INPUT_VERIFICATION_FAILED" });
    const doc = input.ownerDocument;
    const win = doc.defaultView;
    input.focus();
    const focusVerified = doc.activeElement === input || input.isContentEditable;
    if (options.forceFocus && !focusVerified) return { error: "Focus verification failed", code: "INPUT_VERIFICATION_FAILED" };

    if ("value" in input) {
      const prototype = Object.getPrototypeOf(input);
      const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
      if (descriptor?.set) descriptor.set.call(input, prompt); else input.value = prompt;
      this.dispatchInputEvent(input, prompt);
      await new Promise(resolve => win.setTimeout(resolve, 50));
      const actual = String(input.value ?? "");
      if (actual !== prompt) return { error: `Input verification failed: expected ${prompt.length}, got ${actual.length}`, code: "INPUT_VERIFICATION_FAILED" };
      return { input_method: "native_value_setter", input_verified: true, input_text_length: new TextEncoder().encode(actual).length, focus_verified: focusVerified, strategy: "provider_native_send" };
    }

    if (input.isContentEditable || input.getAttribute("contenteditable") === "true") {
      const selection = win.getSelection();
      const range = doc.createRange();
      range.selectNodeContents(input);
      selection.removeAllRanges(); selection.addRange(range);
      let inserted = false;
      try { inserted = doc.execCommand("insertText", false, prompt); } catch (_) {}
      if (!inserted) input.textContent = prompt;
      this.dispatchInputEvent(input, prompt);
      await new Promise(resolve => win.setTimeout(resolve, 50));
      const actual = String(input.textContent || "");
      if (actual !== prompt) return { error: "Contenteditable verification failed", code: "INPUT_VERIFICATION_FAILED" };
      return { input_method: "contenteditable", input_verified: true, input_text_length: new TextEncoder().encode(actual).length, focus_verified: focusVerified, strategy: "provider_native_send" };
    }
    return { error: "Unsupported input element", code: "INPUT_VERIFICATION_FAILED" };
  }

  async submitVerified(input, doc, options = {}) {
    let method = "provider_native_send";
    if (options.simulateEnter) {
      if (!this.inputStrategies(doc).includes("keyboard_enter")) return { error: "Keyboard Enter strategy unavailable", code: "SUBMISSION_FAILED" };
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
      input.dispatchEvent(new KeyboardEvent("keypress", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
      input.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
      method = "keyboard_enter";
    } else {
      const button = this.sendButton(doc);
      if (!button) return { error: "Provider send action unavailable", code: "SUBMISSION_FAILED" };
      button.focus(); button.click();
      method = "provider_native_send";
    }
    const verified = await this.verifySubmission(doc, input);
    if (!verified) return { error: "Provider submission could not be positively verified", code: "SUBMISSION_FAILED" };
    return { provider_submission_verified: true, submit_method: method === "keyboard_enter" ? "keyboard_enter" : "button_click", strategy: method };
  }

  async verifySubmission(doc, input) {
    const beforeText = input && "value" in input ? String(input.value || "") : String(input?.textContent || "");
    const beforeCount = this.responseNodes(doc).length;
    const win = doc.defaultView;
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      if (this.isStreaming(doc)) return true;
      if (this.responseNodes(doc).length > beforeCount) return true;
      const afterText = input && "value" in input ? String(input.value || "") : String(input?.textContent || "");
      if (afterText !== beforeText) return true;
      await new Promise(resolve => win.setTimeout(resolve, 100));
    }
    return false;
  }

  async verifyContinuationSubmission(doc) {
    const win = doc.defaultView;
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      if (this.isStreaming(doc)) return true;
      await new Promise(resolve => win.setTimeout(resolve, 100));
    }
    return false;
  }

  cancel(doc) {
    const stop = this.findBySelectors(doc, ['button[aria-label*="Stop"]', 'button[data-testid*="stop"]', '[data-testid="stop-button"]']);
    if (!stop) return false;
    stop.click();
    this._cancelIssuedAt = Date.now();
    return true;
  }

  inspect(doc) {
    const nodes = this.responseNodes(doc);
    const last = nodes.length ? nodes[nodes.length - 1] : null;
    return {
      provider_context_valid: this.matchesDocument(doc),
      input_ready: !!this.input(doc),
      input_state: this.input(doc) ? "READY" : "NOT_READY",
      authenticated: this.isAuthenticated(doc),
      rate_limited: this.isRateLimited(doc),
      message_count: nodes.length,
      last_message_text: last?.textContent || "",
      streaming: this.isStreaming(doc),
      provider_state: this.isStreaming(doc) ? "busy" : "idle",
    };
  }

  inspectProviderExecution(doc, context = {}) {
    const inspection = this.inspect(doc);
    const baselineCount = Number(context.previous_message_count ?? 0);
    const baselineText = String(context.previous_message_text ?? "");
    const currentText = String(inspection.last_message_text || "");
    const newResponseEvidence = inspection.message_count > baselineCount || currentText !== baselineText;
    return {
      ...inspection,
      authoritative_cessation: !!this._cancelIssuedAt && !inspection.streaming,
      authoritative_completion: !inspection.streaming && newResponseEvidence,
    };
  }
}
