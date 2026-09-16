export class ProviderAdapter {
  constructor(name, url) {
    this.name = name;
    this.url = url;
    this.adapter_version = "1.0.0";
    this.selector_strategy_version = "1.0.0";
    this.supported_features = [
      "streaming",
      "cancel",
      "continuation",
      "diagnostics",
    ];
  }

  deepQuerySelectorAll(doc, selector) {
    const results =
      Array.from(
        doc.querySelectorAll(
          selector
        )
      );

    const seenRoots =
      new Set();

    const walk = root => {
      if (
        !root ||
        seenRoots.has(root)
      ) {
        return;
      }

      seenRoots.add(root);

      for (
        const element of
          root.querySelectorAll?.("*") ||
          []
      ) {
        if (element.shadowRoot) {
          results.push(
            ...element.shadowRoot.querySelectorAll(
              selector
            )
          );

          walk(
            element.shadowRoot
          );
        }
      }
    };

    walk(doc);

    return [
      ...new Set(results)
    ];
  }

  visible(element) {
    if (!element) {
      return false;
    }

    return !!(
      (
        element.offsetWidth > 0 ||
        element.offsetHeight > 0 ||
        element.getClientRects?.().length >
          0
      ) &&
      element.style?.display !==
        "none" &&
      element.style?.visibility !==
        "hidden"
    );
  }

  enabled(element) {
    return !!element &&
      !element.disabled &&
      element.getAttribute(
        "aria-disabled"
      ) !== "true";
  }

  findBySelectors(
    doc,
    selectors
  ) {
    for (
      const selector of
        selectors
    ) {
      const elements =
        this.deepQuerySelectorAll(
          doc,
          selector
        );

      for (
        const element of
          elements
      ) {
        if (
          this.visible(element) &&
          this.enabled(element)
        ) {
          return element;
        }
      }
    }

    return null;
  }

  findAllBySelectors(
    doc,
    selectors
  ) {
    const results = [];

    for (
      const selector of
        selectors
    ) {
      results.push(
        ...this.deepQuerySelectorAll(
          doc,
          selector
        )
      );
    }

    return [
      ...new Set(results)
    ].filter(
      element =>
        this.visible(element)
    );
  }

  findContinueButton(doc) {
    const selectors = [
      'button[data-testid*="continue"]',
      'button[aria-label*="Continue"]',
      'button[aria-label*="continue"]',
      'button[aria-label*="继续"]',
      "button, [role=button]",
    ];

    const isContinue =
      text => {
        const value =
          String(
            text || ""
          )
            .trim()
            .toLowerCase();

        return (
          value ===
            "continue" ||
          value.startsWith(
            "continue"
          ) ||
          value ===
            "继续" ||
          value.includes(
            "继续生成"
          ) ||
          value ===
            "continuer" ||
          value ===
            "continuar" ||
          value ===
            "weiter"
        );
      };

    for (
      const element of
        this.findAllBySelectors(
          doc,
          selectors
        ).reverse()
    ) {
      if (
        isContinue(
          element.textContent
        ) ||
        isContinue(
          element.getAttribute(
            "aria-label"
          )
        )
      ) {
        return element;
      }
    }

    return null;
  }

  input(doc) {
    return this.findBySelectors(
      doc,
      [
        "textarea",
        '[contenteditable="true"]',
      ]
    );
  }

  sendButton(doc) {
    return this.findBySelectors(
      doc,
      [
        'button[aria-label*="Send"]',
        'button[aria-label*="Submit"]',
        'button[type="submit"]',
      ]
    );
  }

  responseNodes(doc) {
    return this.findAllBySelectors(
      doc,
      [
        ".markdown",
        '[data-message-author-role="assistant"]',
      ]
    );
  }

  isStreaming(doc) {
    return !!doc.querySelector(
      '[data-streaming="true"], .loading-indicator, .spinner'
    );
  }

  isAuthenticated(doc) {
    return true;
  }

  isRateLimited(doc) {
    return false;
  }

  dispatchInputEvent(
    input,
    prompt
  ) {
    const win =
      input.ownerDocument
        .defaultView;

    try {
      input.dispatchEvent(
        new InputEvent(
          "input",
          {
            bubbles: true,
            cancelable: true,
            inputType:
              "insertText",
            data:
              prompt,
          }
        )
      );
    } catch (_) {
      input.dispatchEvent(
        new Event(
          "input",
          {
            bubbles: true,
            cancelable: true,
          }
        )
      );
    }

    input.dispatchEvent(
      new Event(
        "change",
        {
          bubbles: true,
        }
      )
    );

    return win;
  }

  async inject(
    input,
    prompt
  ) {
    if (!input) {
      throw Object.assign(
        new Error(
          "Input element is unavailable"
        ),
        {
          code:
            "INPUT_NOT_READY",
        }
      );
    }

    const doc =
      input.ownerDocument;

    const win =
      doc.defaultView;

    input.focus();

    /*
     * Standard HTML input/textarea path.
     *
     * Use the native prototype setter so frameworks such as React/Vue
     * observe an actual value change instead of only seeing a DOM mutation.
     */
    if (
      "value" in input
    ) {
      const prototype =
        Object.getPrototypeOf(
          input
        );

      const descriptor =
        Object.getOwnPropertyDescriptor(
          prototype,
          "value"
        );

      if (
        descriptor?.set
      ) {
        descriptor.set.call(
          input,
          prompt
        );
      } else {
        input.value =
          prompt;
      }

      this.dispatchInputEvent(
        input,
        prompt
      );

      /*
       * Give the page framework a chance to process the input event.
       */
      await new Promise(
        resolve =>
          win.setTimeout(
            resolve,
            50
          )
      );

      const actual =
        String(
          input.value ?? ""
        );

      if (
        actual !== prompt
      ) {
        throw Object.assign(
          new Error(
            `Input verification failed: expected ${prompt.length} characters, got ${actual.length}`
          ),
          {
            code:
              "INPUT_INJECTION_FAILED",
            details: {
              expected_length:
                prompt.length,
              actual_length:
                actual.length,
              actual_text:
                actual,
            },
          }
        );
      }

      return {
        input_method:
          "native_value_setter",
        input_verified:
          true,
        input_text_length:
          actual.length,
      };
    }

    /*
     * Contenteditable path.
     */
    if (
      input.isContentEditable ||
      input.getAttribute(
        "contenteditable"
      ) === "true"
    ) {
      const selection =
        win.getSelection();

      const range =
        doc.createRange();

      range.selectNodeContents(
        input
      );

      selection.removeAllRanges();
      selection.addRange(range);

      let inserted = false;

      try {
        inserted =
          doc.execCommand(
            "insertText",
            false,
            prompt
          );
      } catch (_) {
        inserted = false;
      }

      if (!inserted) {
        input.textContent =
          prompt;
      }

      this.dispatchInputEvent(
        input,
        prompt
      );

      await new Promise(
        resolve =>
          win.setTimeout(
            resolve,
            50
          )
      );

      const actual =
        String(
          input.textContent || ""
        );

      if (
        actual !== prompt
      ) {
        throw Object.assign(
          new Error(
            `Contenteditable verification failed: expected ${prompt.length} characters, got ${actual.length}`
          ),
          {
            code:
              "INPUT_INJECTION_FAILED",
            details: {
              expected_length:
                prompt.length,
              actual_length:
                actual.length,
              actual_text:
                actual,
            },
          }
        );
      }

      return {
        input_method:
          "contenteditable",
        input_verified:
          true,
        input_text_length:
          actual.length,
      };
    }

    throw Object.assign(
      new Error(
        "Unsupported provider input element"
      ),
      {
        code:
          "INPUT_INJECTION_FAILED",
      }
    );
  }

  async submit(
    input,
    doc
  ) {
    const button =
      this.sendButton(doc);

    if (button) {
      button.focus();
      button.click();

      return {
        submit_method:
          "button_click",
      };
    }

    return {
      submit_method:
        "not_available",
    };
  }

  cancel(doc) {
    const stop =
      this.findBySelectors(
        doc,
        [
          'button[aria-label*="Stop"]',
          'button[data-testid*="stop"]',
          '[data-testid="stop-button"]',
        ]
      );

    if (stop) {
      stop.click();
      return true;
    }

    return false;
  }

  inspect(doc) {
    const nodes =
      this.responseNodes(
        doc
      );

    const last =
      nodes.length
        ? nodes[
            nodes.length - 1
          ]
        : null;

    return {
      input_ready:
        !!this.input(doc),

      input_state:
        this.input(doc)
          ? "READY"
          : "NOT_READY",

      authenticated:
        this.isAuthenticated(
          doc
        ),

      rate_limited:
        this.isRateLimited(
          doc
        ),

      message_count:
        nodes.length,

      last_message_text:
        last?.textContent?.trim() ||
        "",

      streaming:
        this.isStreaming(
          doc
        ),

      provider_state:
        this.isStreaming(
          doc
        )
          ? "busy"
          : "idle",
    };
  }
}