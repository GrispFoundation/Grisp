export class ProviderAdapter {
  constructor(name, url) {
    this.name = name;
    this.url = url;
    this.adapter_version = "1.0.0";
    this.selector_strategy_version = "1.0.0";
    this.supported_features = ["streaming", "cancel", "continuation", "diagnostics"];
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
    return !!(
      (element.offsetWidth > 0 || element.offsetHeight > 0 || element.getClientRects?.().length > 0) &&
      element.style?.display !== "none" &&
      element.style?.visibility !== "hidden"
    );
  }

  enabled(element) {
    return !!element && !element.disabled && element.getAttribute("aria-disabled") !== "true";
  }

  findBySelectors(doc, selectors) {
    for (const selector of selectors) {
      const elements = this.deepQuerySelectorAll(doc, selector);
      for (const element of elements) {
        if (this.visible(element) && this.enabled(element)) return element;
      }
    }
    return null;
  }

  findAllBySelectors(doc, selectors) {
    const results = [];
    for (const selector of selectors) {
      results.push(...this.deepQuerySelectorAll(doc, selector));
    }
    return [...new Set(results)].filter(element => this.visible(element));
  }

  findContinueButton(doc) {
    const selectors = [
      'button[data-testid*="continue"]',
      'button[aria-label*="Continue"]',
      'button[aria-label*="continue"]',
      'button[aria-label*="继续"]',
      "button, [role=button]",
    ];
    const isContinue = text => {
      const value = String(text || "").trim().toLowerCase();
      return value === "continue" || value.startsWith("continue") || value === "继续" || value.includes("继续生成") || value === "continuer" || value === "continuar" || value === "weiter";
    };
    for (const element of this.findAllBySelectors(doc, selectors).reverse()) {
      if (isContinue(element.textContent) || isContinue(element.getAttribute("aria-label"))) return element;
    }
    return null;
  }

  input(doc) { return this.findBySelectors(doc, ["textarea", '[contenteditable="true"]']); }
  sendButton(doc) { return this.findBySelectors(doc, ['button[aria-label*="Send"]', 'button[aria-label*="Submit"]', 'button[type="submit"]']); }
  responseNodes(doc) { return this.findAllBySelectors(doc, [".markdown", '[data-message-author-role="assistant"]']); }
  isStreaming(doc) { return !!doc.querySelector('[data-streaming="true"], .loading-indicator, .spinner'); }
  isAuthenticated(doc) { return true; }
  isRateLimited(doc) { return false; }

  async inject(input, prompt) {
    input.focus();
    const doc = input.ownerDocument;
    doc.execCommand("selectAll", false, null);
    doc.execCommand("insertText", false, prompt);
    input.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: prompt }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  async submit(input, doc) {
    const button = this.sendButton(doc);
    if (button) {
      button.click();
      return { submit_method: "button_click" };
    }
    return { submit_method: "not_available" };
  }

  cancel(doc) {
    const stop = this.findBySelectors(doc, ['button[aria-label*="Stop"]', 'button[data-testid*="stop"]', '[data-testid="stop-button"]']);
    if (stop) {
      stop.click();
      return true;
    }
    return false;
  }

  inspect(doc) {
    const nodes = this.responseNodes(doc);
    const last = nodes.length ? nodes[nodes.length - 1] : null;
    return {
      input_ready: !!this.input(doc),
      input_state: this.input(doc) ? "READY" : "NOT_READY",
      authenticated: this.isAuthenticated(doc),
      rate_limited: this.isRateLimited(doc),
      message_count: nodes.length,
      last_message_text: last?.textContent?.trim() || "",
      streaming: this.isStreaming(doc),
      provider_state: this.isStreaming(doc) ? "busy" : "idle",
    };
  }
}
