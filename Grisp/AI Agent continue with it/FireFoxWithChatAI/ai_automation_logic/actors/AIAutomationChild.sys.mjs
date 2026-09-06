/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

export class AIAutomationChild extends JSWindowActorChild {
  async receiveMessage(msg) {
    dump("AIAutomationChild: Received message " + msg.name + "\n");
    try {
      if (msg.name === "AIAutomation:Inject") {
        // msg.data may include flags: prompt, site, forceFocus, simulateEnter
        return await this.inject(msg.data.prompt, msg.data.site, msg.data.forceFocus, msg.data.simulateEnter);
      }
      if (msg.name === "AIAutomation:CheckReady") {
        return this.checkReady(msg.data.site);
      }
      if (msg.name === "AIAutomation:FetchResponse") {
        return this.fetchResponse(msg.data.site, msg.data.prompt);
      }
    } catch (e) {
      dump("AIAutomationChild ERROR: " + e.message + "\n" + e.stack + "\n");
      return { error: e.message, stack: e.stack };
    }
    return null;
  }

  checkReady(site) {
    const handlers = this.getSiteHandlers(this.document);
    const handler = handlers[site] || handlers.default;
    const input = handler.input();
    return !!(input && (input.offsetWidth > 0 || input.offsetHeight > 0));
  }

  /**
   * Deep query selector that pierces shadow DOM boundaries efficiently.
   */
  deepQuerySelectorAll(doc, selector) {
    const results = Array.from(doc.querySelectorAll(selector));
    
    // We only need to walk down to find shadow roots, we don't need to
    // querySelectorAll on every single light-DOM element.
    const walk = (root) => {
      let curr = root.firstElementChild;
      while (curr) {
        if (curr.shadowRoot) {
          results.push(...curr.shadowRoot.querySelectorAll(selector));
          walk(curr.shadowRoot);
        }
        walk(curr);
        curr = curr.nextElementSibling;
      }
    };
    
    walk(doc.body || doc.documentElement);
    return [...new Set(results)]; // Deduplicate
  }

  isElementVisible(el) {
    if (!el) return false;
    return !!(
      (el.offsetWidth > 0 ||
        el.offsetHeight > 0 ||
        (el.getClientRects && el.getClientRects().length > 0)) &&
      el.style.display !== "none" &&
      el.style.visibility !== "hidden"
    );
  }

  isElementDisabled(el) {
    if (!el) return true;
    return (
      el.disabled === true ||
      el.getAttribute("aria-disabled") === "true" ||
      el.classList.contains("disabled") ||
      el.classList.contains("is-disabled")
    );
  }

  isContinueText(text) {
    if (!text || text.length > 50) return false;
    const lower = text.trim().toLowerCase();
    return (
      lower === "continue" ||
      lower === "continue generating" ||
      lower === "continue writing" ||
      lower === "continue response" ||
      lower.startsWith("continue") ||
      lower === "继续生成" ||
      lower === "继续" ||
      lower.includes("继续生成") ||
      lower === "continuer" ||
      lower === "continuar" ||
      lower === "weiter"
    );
  }

  findContinueButton(doc, site = "default") {
    const selectors = [
      "button.ds-button.ds-button--secondary",
      "button.ds-button",
      ".ds-button",
      '[data-testid*="continue"]',
      'button[aria-label*="Continue"]',
      'button[aria-label*="continue"]',
      'button[aria-label*="继续"]',
      'button, div[role="button"], a[role="button"], span[role="button"], [class*="button"], [class*="btn"]',
    ];

    const candidates = Array.from(
      this.deepQuerySelectorAll(doc, selectors.join(", "))
    ).reverse();

    for (const el of candidates) {
      if (this.isElementVisible(el) && !this.isElementDisabled(el)) {
        const text = (el.textContent || "").trim().toLowerCase();
        const aria = (el.getAttribute("aria-label") || "").trim().toLowerCase();
        if (this.isContinueText(text) || this.isContinueText(aria)) {
          return el;
        }
      }
    }

    return null;
  }

  clickElement(el) {
    if (!el) return;
    try {
      el.focus();
      const win = this.contentWindow;
      el.dispatchEvent(
        new MouseEvent("mouseenter", {
          bubbles: true,
          cancelable: true,
          view: win,
        })
      );
      el.dispatchEvent(
        new MouseEvent("mouseover", {
          bubbles: true,
          cancelable: true,
          view: win,
        })
      );
      el.dispatchEvent(
        new MouseEvent("mousedown", {
          bubbles: true,
          cancelable: true,
          view: win,
          button: 0,
        })
      );
      el.dispatchEvent(
        new MouseEvent("mouseup", {
          bubbles: true,
          cancelable: true,
          view: win,
          button: 0,
        })
      );
      el.dispatchEvent(
        new MouseEvent("click", {
          bubbles: true,
          cancelable: true,
          view: win,
          button: 0,
        })
      );
      el.click();
    } catch (e) {
      dump("AIAutomationChild: Error clicking element: " + e.message + "\n");
      try {
        el.click();
      } catch (_e) {}
    }
  }

  /**
   * Fetch the latest AI response text from the page.
   * Returns { text, done, continued } where done=true means streaming has finished.
   * Returns { pending: true, debug: [...] } if the response hasn't started yet.
   */
  fetchResponse(site, passedPrompt = null) {
    const doc = this.document;
    const handlers = this.getSiteHandlers(doc);
    const handler = handlers[site] || handlers.default;
    let messages = handler.response();
    
    let activePrompt = passedPrompt || this.lastInjectedPrompt;

    if (messages && messages.length && activePrompt) {
      // Filter out user prompts that got scraped
      let filtered = Array.from(messages).filter(m => {
        let text = m.textContent.trim();
        return text && text !== activePrompt && !text.startsWith(activePrompt);
      });
      messages = filtered;
    }

    let debugDetails = [];

    if (!messages || !messages.length) {
      debugDetails.push(`NO message elements found for ${site}.`);
      
      // DEEP DEBUG: Grab snippets of the longest text blocks on the page to see what Copilot rendered
      let allTextDivs = Array.from(doc.querySelectorAll("div, p, span"))
        .map(n => n.textContent.trim())
        .filter(t => t.length > 50);
      
      // Keep longest 3
      allTextDivs.sort((a, b) => b.length - a.length);
      debugDetails.push(`Top 3 text nodes on page:`);
      for (let i = 0; i < Math.min(3, allTextDivs.length); i++) {
        debugDetails.push(`[${i}] ${allTextDivs[i].substring(0, 80)}...`);
      }

      return { pending: true, debug: debugDetails };
    }

    // Look for a "thinking" / streaming indicator to know if we're done
    const isStreaming = handler.isStreaming ? handler.isStreaming() : false;

    // Check for "Continue" button
    const continueBtn = handler.continueButton
      ? handler.continueButton()
      : this.findContinueButton(doc, site);

    const now = Date.now();
    const isRecentContinue =
      this.lastContinueClickTime && now - this.lastContinueClickTime < 3000;

    let continued = false;
    if (continueBtn && !isRecentContinue) {
      dump(
        "AIAutomationChild: Detected Continue button for " +
          site +
          ", clicking it...\n"
      );
      this.lastContinueClickTime = now;
      this.clickElement(continueBtn);
      continued = true;
    }

    const hasContinue = !!continueBtn || isRecentContinue;
    const isDone = !isStreaming && !hasContinue;

    const lastMsg = messages[messages.length - 1];
    const text = lastMsg.textContent.trim();

    if (!text) {
      debugDetails.push(`Found message elements, but text was empty.`);
      return { pending: true, debug: debugDetails };
    }

    return { text, done: isDone, continued, site };
  }

  getSiteHandlers(doc) {
    return {
      grok: {
        input: () =>
          doc.querySelector(
            '.tiptap.ProseMirror, textarea[placeholder*="know"], textarea[placeholder*="What"]'
          ),
        button: () =>
          doc.querySelector(
            'button[aria-label="Submit"], button[data-testid*="send"]'
          ),
        response: () =>
          doc.querySelectorAll(".items-start .response-content-markdown"),
        isStreaming: () => !!doc.querySelector('[data-streaming="true"], .loading-indicator, .spinner'),
        inject: async (el, text) => {
          el.focus();
          doc.execCommand("selectAll", false, null);
          doc.execCommand("insertText", false, text);
          el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: text }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        },
      },
      gemini: {
        input: () => doc.querySelector(".ql-editor"),
        button: () =>
          doc.querySelector(
            'button[aria-label*="Send"], button[aria-label*="send"]'
          ),
        response: () =>
          doc.querySelectorAll(
            "model-response .markdown, .model-response-text .markdown, " +
            ".response-container .markdown, model-response, " +
            ".message-content.model .markdown"
          ),
        // Gemini shows a "stop" button while streaming
        isStreaming: () =>
          !!doc.querySelector(
            'button[aria-label*="Stop"], .loading-indicator, ' +
            'mat-progress-bar, .response-loading'
          ),
        inject: async (el, text) => {
          el.focus();
          doc.execCommand("selectAll", false, null);
          doc.execCommand("insertText", false, text);
          el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: text }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        },
      },
      chatgpt: {
        input: () => doc.querySelector("#prompt-textarea"),
        button: () => doc.querySelector('button[data-testid*="send"], button[aria-label*="Send"]'),
        response: () =>
          doc.querySelectorAll(
            '[data-message-author-role="assistant"] .markdown, ' +
            '.agent-turn .markdown, ' +
            'div[data-testid*="conversation-turn"] .markdown'
          ),
        isStreaming: () =>
          !!doc.querySelector('[data-testid="stop-button"], .result-streaming'),
        continueButton: () => this.findContinueButton(doc, "chatgpt"),
        inject: async (el, text) => {
          el.focus();
          doc.execCommand("selectAll", false, null);
          doc.execCommand("insertText", false, text);
          
          // React 18+ contenteditable requires a true InputEvent to trigger the onChange listener
          el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: text }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        },
      },
      copilot: {
        input: () =>
          // Try many known Copilot textarea selectors across redesigns
          doc.querySelector(
            'textarea#userInput, ' +
            'textarea[placeholder*="Message"], ' +
            'textarea[placeholder*="Ask"], ' +
            'textarea[placeholder*="Copilot"], ' +
            'textarea[placeholder*="message"], ' +
            '[data-testid="composer-input"] textarea, ' +
            '[data-testid="chat-input"] textarea, ' +
            '.cib-text-input, ' +
            '#searchbox, ' +
            'textarea[aria-label*="Ask"], ' +
            '[aria-label*="Copilot"] textarea, ' +
            'div[contenteditable="true"][role="textbox"], ' +
            'textarea'
          ),
        button: () =>
          doc.querySelector(
            'button[aria-label*="Submit"], ' +
            'button[aria-label*="Send"], ' +
            'button[aria-label*="submit"], ' +
            'button[data-testid*="send"], ' +
            'button[type="submit"]'
          ),
        response: () => {
          // Try selectors from every known Copilot DOM redesign
          let sel = this.deepQuerySelectorAll(
            doc,
            // New Copilot (2024-2025) — sydney/bing chat style
            'cib-message-group[source="bot"] cib-message .content, ' +
            '.cib-message-content, ' +
            // Fluent Copilot redesign
            '[data-testid="ai-response"], ' +
            '[data-testid*="response"] .content, ' +
            // Generic response wrappers
            '.response-message, .bot-message, ' +
            // ac-container items (Adaptive Cards)
            '.ac-container, ' +
            // message-bubble from older builds
            '.message-bubble, ' +
            // Assistant role items
            '[class*="assistant"][class*="message"], ' +
            '[class*="bot"][class*="message"], ' +
            // Fallback: any markdown container in a response area
            '.response-text, .answer-text, ' +
            '[class*="ResponseText"], [class*="responseText"]'
          );

          // If standard selectors fail, use a structural fallback based on screen-reader text
          if (sel.length === 0) {
            // Find any element containing "Copilot said" and grab its parent or next sibling
            let walkers = this.deepQuerySelectorAll(doc, "div, span, p");
            let copilotBlocks = walkers.filter(n => {
              let text = n.textContent.trim();
              return text.includes("Copilot said") && text.length > 50; 
            });
            
            if (copilotBlocks.length > 0) {
              // Extract just the part after the last "Copilot said"
              let fullText = copilotBlocks[copilotBlocks.length - 1].textContent;
              let parts = fullText.split(/Copilot said|Bing said/);
              let lastMsgText = parts[parts.length - 1];
              
              // Return a pseudo-element array so fetchResponse works normally
              return [{ textContent: lastMsgText }];
            }
          }

          return sel;
        },
        isStreaming: () => {
          const streamingNodes = this.deepQuerySelectorAll(
            doc,
            '.loading-dots, .typing-indicator, ' +
            '[data-testid="stop-button"], ' +
            'button[aria-label*="Stop"], ' +
            '.cib-stop-responding-button'
          );
          return streamingNodes.length > 0;
        },
        inject: async (el, text) => {
          el.focus();
          // execCommand is the reliable cross-framework injection method —
          // it works for React, Vue, plain textareas and contenteditable divs.
          doc.execCommand("selectAll", false, null);
          doc.execCommand("insertText", false, text);
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(new Event("change", { bubbles: true }));

          // Retry clicking the send button — Copilot needs a moment for
          // React to re-enable the button after text is entered.
          // Doing this here prevents the outer inject from falling through
          // to simulateEnter (which triggers the IPC crash).
          for (let attempt = 0; attempt < 8; attempt++) {
            await new Promise(r => this.contentWindow.setTimeout(r, 300));
            const btn = doc.querySelector(
              'button[aria-label*="Submit"], button[aria-label*="Send"], ' +
              'button[aria-label*="submit"], button[data-testid*="send"], ' +
              'button[type="submit"]'
            );
            if (btn && !btn.disabled) {
              dump("AIAutomationChild: Copilot send button found, clicking\n");
              btn.click();
              return; // submission handled — outer inject will skip
            }
          }
          dump("AIAutomationChild: Copilot send button never enabled after retries\n");
        },
      },
      deepseek: {
        input: () =>
          doc.querySelector(
            'textarea.ds-input__input, textarea#chat-input, textarea[placeholder*="DeepSeek"]'
          ),
        button: () =>
          doc.querySelector(
            'div[role="button"]._52c986b, button.ds-icon-button, button[aria-label*="Send"], [data-testid*="send"]'
          ),
        response: () =>
          doc.querySelectorAll(".ds-markdown, .ds-message-bubble, .markdown"),
        isStreaming: () =>
          !!doc.querySelector(
            '.ds-loading, [class*="loading"], .spinner, [class*="spinner"], [data-streaming="true"]'
          ),
        continueButton: () => this.findContinueButton(doc, "deepseek"),
        inject: async (el, text) => {
          el.focus();
          await new Promise(r => this.contentWindow.setTimeout(r, 1000));
          doc.execCommand("selectAll", false, null);
          doc.execCommand("insertText", false, text);
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(
            new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
          );
          await new Promise(r => this.contentWindow.setTimeout(r, 100));
          el.dispatchEvent(
            new KeyboardEvent("keyup", { key: "Enter", bubbles: true })
          );
          await new Promise(r => this.contentWindow.setTimeout(r, 500));
        },
      },
      claude: {
        input: () =>
          doc.querySelector(
            'div[contenteditable="true"], [aria-label*="Claude"]'
          ),
        button: () =>
          doc.querySelector(
            'button[aria-label*="Send"], button[style*="background-color"]'
          ),
        response: () =>
          doc.querySelectorAll(".font-claude-message, .markdown"),
        isStreaming: () => !!doc.querySelector('.loading-indicator, [class*="streaming"]'),
        continueButton: () => this.findContinueButton(doc, "claude"),
        inject: async (el, text) => {
          el.focus();
          doc.execCommand("selectAll", false, null);
          doc.execCommand("insertText", false, text);
          el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: text }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        },
      },
      perplexity: {
        input: () => {
          let lightNode = doc.querySelector(
            'textarea, [contenteditable="true"], [placeholder*="Ask"], [placeholder*="anything"], input[type="text"]'
          );
          if (lightNode) return lightNode;
          // Fallback to shadow piercing
          return this.deepQuerySelectorAll(
            doc,
            'textarea, [contenteditable="true"], [placeholder*="Ask"]'
          )[0];
        },
        button: () => {
          let lightBtn = doc.querySelector(
            'button[aria-label*="Submit"], button[class*="send"], button[aria-label*="Send"], ' +
            'button[aria-label*="Ask"]'
          );
          if (lightBtn) return lightBtn;
          return this.deepQuerySelectorAll(
            doc,
            'button[aria-label*="Submit"], button[aria-label*="Send"]'
          )[0];
        },
        response: () =>
          doc.querySelectorAll(".prose, .markdown, .break-words"),
        isStreaming: () => !!doc.querySelector('.loading-indicator, [class*="loading"]'),
        continueButton: () => this.findContinueButton(doc, "perplexity"),
        inject: async (el, text) => {
          el.focus();
          if (
            el.tagName === "DIV" ||
            el.getAttribute("contenteditable") === "true"
          ) {
            doc.execCommand("selectAll", false, null);
            doc.execCommand("insertText", false, text);
          } else {
            doc.execCommand("selectAll", false, null);
            doc.execCommand("insertText", false, text);
          }
          el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: text }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        },
      },
      inception: {
        input: () => doc.querySelector("textarea"),
        button: () => doc.querySelector('button[aria-label*="Send"]'),
        response: () => doc.querySelectorAll(".prose-chat, .markdown"),
        isStreaming: () => !!doc.querySelector('.loading-indicator, [class*="loading"]'),
        continueButton: () => this.findContinueButton(doc, "inception"),
        inject: async (el, text) => {
          el.focus();
          await new Promise(r => this.contentWindow.setTimeout(r, 1000));
          doc.execCommand("selectAll", false, null);
          doc.execCommand("insertText", false, text);
          el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: text }));
          el.dispatchEvent(
            new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
          );
          await new Promise(r => this.contentWindow.setTimeout(r, 100));
          el.dispatchEvent(
            new KeyboardEvent("keyup", { key: "Enter", bubbles: true })
          );
          await new Promise(r => this.contentWindow.setTimeout(r, 500));
        },
      },
      default: {
        input: () =>
          doc.querySelector(
            'textarea, [contenteditable="true"], input[type="text"]'
          ),
        button: () =>
          doc.querySelector(
            'button[aria-label*="Send"], button[aria-label="Submit"]'
          ),
        response: () =>
          doc.querySelectorAll(
            '.message, [class*="message"], .markdown, .conversation-item'
          ),
        isStreaming: () => false,
        continueButton: () => this.findContinueButton(doc, "default"),
        inject: async (el, text) => {
          el.focus();
          if (
            el.tagName === "DIV" ||
            el.getAttribute("contenteditable") === "true"
          ) {
            doc.execCommand("selectAll", false, null);
            doc.execCommand("insertText", false, text);
          } else {
            doc.execCommand("selectAll", false, null);
            doc.execCommand("insertText", false, text);
          }
          el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: true, inputType: "insertText", data: text }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        },
      },
    };
  }

  /**
   * inject now accepts optional flags forceFocus and simulateEnter.
   * The child actor will attempt to focus the window/tab and let site-specific
   * handlers perform the submit. If the handler does not click the send button,
   * simulateEnter will be used as a safe fallback.
   */
  async inject(prompt, site, forceFocus = false, simulateEnterFlag = false) {
    dump("AIAutomationChild: Starting site-specific inject for " + site + "\n");
    this.lastInjectedPrompt = prompt.trim();
    const doc = this.document;
    const handlers = this.getSiteHandlers(doc);
    const handler = handlers[site] || handlers.default;
    const input = handler.input();

    if (!input) {
      dump("AIAutomationChild: ERROR - Input not found for " + site + "\n");
      return { error: "Input not found" };
    }

    // If requested, try to focus the content window/tab before injecting.
    if (forceFocus) {
      try {
        if (this.contentWindow && typeof this.contentWindow.focus === "function") {
          this.contentWindow.focus();
          dump("AIAutomationChild: Forced focus on content window\n");
        }
      } catch (e) {
        dump("AIAutomationChild: forceFocus failed: " + e.message + "\n");
      }
    }

    dump("AIAutomationChild: Found input, injecting text...\n");
    // handler.inject() may handle its own button click (e.g. Copilot).
    // Track the send button state BEFORE inject to detect if handler clicked it.
    const btnBefore = handler.button();
    const disabledBefore = !btnBefore || btnBefore.disabled;

    await handler.inject(input, prompt);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));

    // Check if the send button was already clicked inside handler.inject
    // (e.g. Copilot retries internally). If the button is now disabled or
    // gone it was most likely clicked — skip the outer submit to avoid a
    // double-send or IPC crash.
    const btnAfter = handler.button();
    const clickedByHandler = btnAfter && btnAfter.disabled;
    if (clickedByHandler) {
      dump("AIAutomationChild: Submit handled by site handler, skipping outer click\n");
    } else {
      // Retry the button a few times with small gaps to let React settle.
      let sent = false;
      for (let attempt = 0; attempt < 10 && !sent; attempt++) {
        await new Promise(r => this.contentWindow.setTimeout(r, 300));
        const sendBtn = handler.button();
        if (sendBtn && !sendBtn.disabled) {
          dump("AIAutomationChild: Clicking send button (attempt " + (attempt + 1) + ")\n");
          sendBtn.click();
          sent = true;
        }
      }
      if (!sent) {
        dump("AIAutomationChild: Send button unavailable — using safe fallback\n");
        // Use simulateEnter only if explicitly requested by the parent to avoid unsafe key events.
        if (simulateEnterFlag) {
          this.simulateEnter(input);
        } else {
          dump("AIAutomationChild: simulateEnter not requested; leaving as-is\n");
        }
      }
    }

    // Return immediately — do NOT wait for the response here.
    // The parent will poll FetchResponse on the (possibly new) page actor.
    dump("AIAutomationChild: Inject complete, returning injected status\n");
    return { status: "injected" };
  }

  simulateEnter(el) {
    // Do NOT use KeyboardEvent here — Firefox dispatches a sync
    // RequestNativeKeyBindings IPC message for key events which crashes
    // the tab if the parent process isn't ready to handle it.
    //
    // Safe alternatives in order of preference:
    //   1. form.submit() — works for classic HTML forms
    //   2. execCommand("insertParagraph") — works for contenteditable
    //   3. execCommand("insertText", false, "\n") — textarea fallback
    const doc = this.document;
    const form = el.closest("form");
    if (form) {
      dump("AIAutomationChild: simulateEnter via form.submit()\n");
      form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
      return;
    }
    if (
      el.getAttribute("contenteditable") === "true" ||
      el.tagName === "DIV"
    ) {
      dump("AIAutomationChild: simulateEnter via execCommand(insertParagraph)\n");
      doc.execCommand("insertParagraph", false, null);
      return;
    }
    // textarea fallback — insert a newline character, which some frameworks
    // interpret as a submit trigger
    dump("AIAutomationChild: simulateEnter via execCommand(insertText, \\n)\n");
    el.focus();
    doc.execCommand("insertText", false, "\n");
  }
}
