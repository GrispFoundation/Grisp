/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  BrowserWindowTracker: "resource:///modules/BrowserWindowTracker.sys.mjs",
  setTimeout: "resource://gre/modules/Timer.sys.mjs",
  setInterval: "resource://gre/modules/Timer.sys.mjs",
  clearInterval: "resource://gre/modules/Timer.sys.mjs",
});

const PORT = 9999;

export class AIAutomationService {
  constructor() {
    this.serverSocket = null;
    this.connections = new Set();
  }

  init() {
    try {
      this.serverSocket = Cc[
        "@mozilla.org/network/server-socket;1"
      ].createInstance(Ci.nsIServerSocket);
      this.serverSocket.init(PORT, true, -1);
      this.serverSocket.asyncListen(this);
      dump(`AIAutomationService: Listening on port ${PORT}\n`);
    } catch (e) {
      dump(`AIAutomationService: Failed to start server socket: ${e}\n`);
    }
  }

  // nsIServerSocketListener
  onSocketAccepted(_socket, transport) {
    dump(`AIAutomationService: Connection accepted\n`);
    let connection = new AIAutomationConnection(transport, this);
    this.connections.add(connection);
  }

  onStopListening(_socket, _status) {
    this.serverSocket = null;
  }

  removeConnection(conn) {
    this.connections.delete(conn);
  }
}

class AIAutomationConnection {
  constructor(transport, service) {
    this.transport = transport;
    this.service = service;
    this.outStream = transport.openOutputStream(0, 0, 0);
    this.inStream = transport.openInputStream(0, 0, 0);
    this.pump = Cc["@mozilla.org/network/input-stream-pump;1"].createInstance(
      Ci.nsIInputStreamPump
    );
    this.pump.init(this.inStream, 0, 0, false);
    this.pump.asyncRead(this);
    this.data = "";
  }

  onStartRequest(_request) {}

  onStopRequest(_request, _status) {
    this.service.removeConnection(this);
  }

  onDataAvailable(_request, stream, _offset, count) {
    let binaryStream = Cc["@mozilla.org/binaryinputstream;1"].createInstance(
      Ci.nsIBinaryInputStream
    );
    binaryStream.setInputStream(stream);
    let bytes = new Uint8Array(binaryStream.readByteArray(count));
    if (!this.decoder) {
      this.decoder = new TextDecoder();
    }
    this.data += this.decoder.decode(bytes, { stream: true });

    if (this.data.includes("\n")) {
      let lines = this.data.split("\n");
      this.data = lines.pop();
      for (let line of lines) {
        if (line.trim()) {
          this.handleCommand(line.trim());
        }
      }
    }
  }

  async handleCommand(line) {
    try {
      let cmd = JSON.parse(line);
      let response = await this.executeCommand(cmd);
      this.sendResponse(response);
    } catch (e) {
      this.sendResponse({ error: e.message });
    }
  }

  async executeCommand(cmd) {
    try {
      switch (cmd.command) {
        case "getTabs":
          return AIAutomationUtils.getTabs();
        case "openTab":
          return AIAutomationUtils.openTab(cmd.url);
        case "duplicateTab":
          return AIAutomationUtils.duplicateTab(cmd.tab);
        case "closeTab":
          return AIAutomationUtils.closeTab(cmd.tab);
        case "prompt":
          // Pass the entire command object so flags like forceFocus, simulateEnter, settleMs are available
          return AIAutomationUtils.handlePrompt(cmd);
        default:
          return { error: "Unknown command: " + cmd.command };
      }
    } catch (e) {
      return { error: e.message, stack: e.stack };
    }
  }

  sendResponse(resp) {
    try {
      let msg = JSON.stringify(resp) + "\n";
      let binaryOut = Cc["@mozilla.org/binaryoutputstream;1"].createInstance(
        Ci.nsIBinaryOutputStream
      );
      binaryOut.setOutputStream(this.outStream);
      let bytes = new TextEncoder().encode(msg);
      binaryOut.writeByteArray(bytes, bytes.length);
    } catch (e) {
      dump(`AIAutomationService: Failed to send response: ${e}\n`);
    }
  }
}

const AIAutomationUtils = {
  findTab(spec) {
    let win = lazy.BrowserWindowTracker.getTopWindow();
    if (!win) {
      return null;
    }

    if (
      typeof spec === "number" ||
      (typeof spec === "string" && spec.length > 0 && !isNaN(spec))
    ) {
      let index = parseInt(spec);
      if (index >= 0 && index < win.gBrowser.tabs.length) {
        return win.gBrowser.tabs[index];
      }
    }

    if (typeof spec === "string" && spec.length > 0) {
      let lowerSpec = spec.toLowerCase();
      // Try exact URL match first
      for (let tab of win.gBrowser.tabs) {
        if (tab.linkedBrowser.currentURI.spec === spec) {
          return tab;
        }
      }
      // Try title match
      for (let tab of win.gBrowser.tabs) {
        if (tab.label.toLowerCase().includes(lowerSpec)) {
          return tab;
        }
      }
      // Try URL contains
      for (let tab of win.gBrowser.tabs) {
        if (
          tab.linkedBrowser.currentURI.spec.toLowerCase().includes(lowerSpec)
        ) {
          return tab;
        }
      }
    }
    return null;
  },

  getTabs() {
    let win = lazy.BrowserWindowTracker.getTopWindow();
    if (!win) return { error: "No browser window found" };

    let tabs = [];
    for (let i = 0; i < win.gBrowser.tabs.length; i++) {
      let tab = win.gBrowser.tabs[i];
      tabs.push({
        index: i,
        title: tab.label,
        url: tab.linkedBrowser.currentURI.spec,
        selected: tab.selected,
      });
    }
    return { tabs };
  },

  openTab(url) {
    let win = lazy.BrowserWindowTracker.getTopWindow();
    if (!win) return { error: "No browser window found" };
    let tab = win.gBrowser.addTrustedTab(url);
    win.gBrowser.selectedTab = tab;
    return { index: win.gBrowser.tabs.indexOf(tab), url };
  },

  duplicateTab(spec) {
    let win = lazy.BrowserWindowTracker.getTopWindow();
    if (!win) return { error: "No browser window found" };
    let tab = AIAutomationUtils.findTab(spec);
    if (!tab) return { error: "Tab not found for spec: " + spec };
    let newTab = win.gBrowser.duplicateTab(tab);
    win.gBrowser.selectedTab = newTab;
    return { index: win.gBrowser.tabs.indexOf(newTab) };
  },

  closeTab(spec) {
    let win = lazy.BrowserWindowTracker.getTopWindow();
    if (!win) return { error: "No browser window found" };
    let tab = AIAutomationUtils.findTab(spec);
    if (!tab) return { error: "Tab not found for spec: " + spec };
    win.gBrowser.removeTab(tab);
    return { success: true };
  },

  /**
   * handlePrompt now accepts the full command object so optional flags
   * from the proxy (forceFocus, simulateEnter, settleMs) are honored.
   */
  async handlePrompt(cmd) {
    const site = cmd.site;
    const text = cmd.text;
    const tabSpec = cmd.tab ?? -1;
    const forceFocus = !!cmd.forceFocus;
    const simulateEnterFlag = !!cmd.simulateEnter;
    // settleMs if provided; otherwise site-aware default will be used by pollForResponse
    const settleMsOverride = typeof cmd.settleMs === "number" ? cmd.settleMs : null;

    const urls = {
      copilot: "https://copilot.microsoft.com/",
      gemini: "https://gemini.google.com/app",
      grok: "https://grok.com/",
      deepseek: "https://chat.deepseek.com/",
      inception: "https://chat.inceptionlabs.ai/",
      chatgpt: "https://chatgpt.com/",
      claude: "https://claude.ai/",
      perplexity: "https://www.perplexity.ai/",
    };

    try {
      let win = lazy.BrowserWindowTracker.getTopWindow();
      if (!win) {
        throw new Error("No browser window found");
      }

      let tab = AIAutomationUtils.findTab(tabSpec);
      if (tab) {
        win.gBrowser.selectedTab = tab;
        if (!site) {
          let tabUrl = tab.linkedBrowser.currentURI.spec.toLowerCase();
          for (let [s, u] of Object.entries(urls)) {
            if (tabUrl.includes(s)) {
              cmd.site = s;
              break;
            }
          }
          if (!cmd.site) cmd.site = "default";
        }
        dump(
          "AIAutomation: Re-using tab " +
            win.gBrowser.tabs.indexOf(tab) +
            " for " +
            cmd.site +
            "\n"
        );
      } else {
        let url = urls[cmd.site];
        if (!url) {
          throw new Error("Unknown site: " + cmd.site);
        }
        dump("AIAutomation: Opening new tab for " + cmd.site + "\n");
        tab = win.gBrowser.addTrustedTab(url);
        win.gBrowser.selectedTab = tab;
      }

      let browser = tab.linkedBrowser;

      // --- Phase 1: Wait for the page to be ready ---
      dump("AIAutomation: Initializing smart polling for " + cmd.site + "...\n");
      await AIAutomationUtils.waitForReady(browser, cmd.site, win);

      // Check for login redirects
      let currentURI = browser.currentURI.spec;
      if (
        currentURI.includes("sign_in") ||
        currentURI.includes("login") ||
        currentURI.includes("auth") ||
        currentURI.includes("/checkpoint/")
      ) {
        let msg = "AIAutomation: Login redirect detected: " + currentURI;
        dump(msg + "\n");
        Services.console.logStringMessage(msg);
        return {
          error: "Please sign in to " + cmd.site + " manually in the browser first.",
        };
      }

      // --- Phase 2: Inject the prompt (actor returns immediately after send) ---
      dump("AIAutomation: Contacting actor for " + cmd.site + "\n");
      let actor = AIAutomationUtils.getActor(browser);
      if (!actor) {
        throw new Error("Could not find AIAutomation actor");
      }

      // Pass flags to the child actor so it can focus and simulate enter safely
      let injectPayload = {
        prompt: text,
        site: cmd.site,
        forceFocus,
        simulateEnter: simulateEnterFlag,
      };

      let injectResult = await actor.sendQuery("AIAutomation:Inject", injectPayload);

      if (injectResult && injectResult.error) {
        return injectResult;
      }
      dump(
        "AIAutomation: Inject confirmed: " +
          JSON.stringify(injectResult) +
          "\n"
      );

      // --- Phase 3: Poll for response in the parent (survives SPA navigation) ---
      dump("AIAutomation: Polling for response on " + cmd.site + "...\n");
      let result = await AIAutomationUtils.pollForResponse(browser, cmd.site, win, text, settleMsOverride);
      dump("AIAutomation: Final result: " + JSON.stringify(result) + "\n");
      return result;
    } catch (e) {
      let errorMsg = "AIAutomation ERROR: " + e.message + "\n" + e.stack;
      dump(errorMsg + "\n");
      Services.console.logStringMessage(errorMsg);
      return { error: e.message };
    }
  },

  getActor(browser) {
    if (
      browser.browsingContext &&
      browser.browsingContext.currentWindowGlobal
    ) {
      return browser.browsingContext.currentWindowGlobal.getActor(
        "AIAutomation"
      );
    }
    return null;
  },

  /**
   * Waits until the page's AI input box is visible and ready.
   * Resolves on readiness, login redirect, or timeout (30s).
   */
  waitForReady(browser, site, win) {
    return new Promise(resolve => {
      let iterations = 0;
      let resolved = false;
      let intervalId = null;

      const done = reason => {
        if (!resolved) {
          dump("AIAutomation: Readiness check finished (" + reason + ")\n");
          resolved = true;
          if (intervalId) {
            lazy.clearInterval(intervalId);
          }
          resolve();
        }
      };

      intervalId = lazy.setInterval(async () => {
        iterations++;

        try {
          let currentURI = browser.currentURI.spec;

          // Stop on auth redirects — caller handles it
          if (
            currentURI.includes("sign_in") ||
            currentURI.includes("login") ||
            currentURI.includes("auth") ||
            currentURI.includes("/checkpoint/")
          ) {
            done("login-redirect");
            return;
          }

          if (
            browser.browsingContext &&
            browser.browsingContext.currentWindowGlobal
          ) {
            let actor = browser.browsingContext.currentWindowGlobal.getActor(
              "AIAutomation"
            );
            if (actor) {
              let isReady = await actor.sendQuery("AIAutomation:CheckReady", {
                site,
              });
              if (isReady) {
                done("ready");
                return;
              }
            }
          }
        } catch (_e) {
          // Actor not ready yet — keep polling
        }

        if (iterations % 6 === 0) {
          dump(
            "AIAutomation: Still polling for " +
              site +
              " (URI: " +
              browser.currentURI.spec +
              ")...\n"
          );
        }

        if (iterations > 60) {
          done("timeout");
        }
      }, 500);
    });
  },

  /**
   * Polls the content actor for the AI response.
   * This runs entirely in the parent/chrome process, so it survives
   * SPA navigations that destroy and recreate the child actor.
   *
   * Strategy:
   *  - Wait for settleMs (site-aware default or override) before polling.
   *  - Then poll FetchResponse every 500ms.
   *  - When we see stable text (unchanged for 3s) AND done=true, resolve.
   *  - Timeout after 120s.
   */
  pollForResponse(browser, site, win, prompt, settleMsOverride = null) {
    return new Promise((resolve, reject) => {
      // Determine settle delay: use override if provided, otherwise site-aware default.
      const SPA_SITES = ["gemini", "chatgpt", "perplexity", "inception"];
      const defaultSettleMs = SPA_SITES.includes(site) ? 3000 : 1000;
      const settleMs = typeof settleMsOverride === "number" ? settleMsOverride : defaultSettleMs;

      dump("AIAutomation: Settle delay " + settleMs + "ms for " + site + "\n");

      lazy.setTimeout(() => {
        let iterations = 0;
        let noProgressIterations = 0;
        let lastText = "";
        let stableCount = 0;
        let resolved = false;
        let intervalId = null;

        const done = result => {
          if (!resolved) {
            resolved = true;
            if (intervalId) {
              lazy.clearInterval(intervalId);
            }
            resolve(result);
          }
        };

        intervalId = lazy.setInterval(async () => {
          iterations++;
          noProgressIterations++;

          try {
            if (iterations % 20 === 0) {
              dump(
                "AIAutomation: Waiting for " +
                  site +
                  " response... (tick " +
                  iterations +
                  ", idle " +
                  noProgressIterations +
                  "/240)\n"
              );
            }

            // Re-acquire actor each tick — handles SPA navigation
            let actor = AIAutomationUtils.getActor(browser);
            if (!actor) {
              // Page might be mid-navigation; keep waiting
              if (iterations % 10 === 0) {
                dump(
                  "AIAutomation: Waiting for actor after navigation...\n"
                );
              }
              return;
            }

            let resp = await actor.sendQuery("AIAutomation:FetchResponse", {
              site,
              prompt,
            });

            if (!resp || resp.pending) {
              // Response not visible yet
              if (resp && resp.debug && iterations % 20 === 0) {
                dump("AIAutomation: FetchResponse debug: " + JSON.stringify(resp.debug) + "\n");
              }
              if (noProgressIterations > 240) {
                dump("AIAutomation: TIMEOUT waiting for response\n");
                done({
                  error: "Timeout waiting for response",
                  lastSeen: lastText,
                  site,
                });
              }
              return;
            }

            const currentText = resp.text || "";

            if (resp.continued) {
              dump(
                "AIAutomation: Continue button clicked on " +
                  site +
                  ", waiting for continuation...\n"
              );
              stableCount = 0;
              noProgressIterations = 0; // Reset progress timeout
            }

            if (currentText && currentText === lastText) {
              stableCount++;
            } else {
              if (currentText) {
                dump(
                  "AIAutomation: Response text changing: " +
                    currentText.substring(0, 40) +
                    "...\n"
                );
              }
              stableCount = 0;
              noProgressIterations = 0; // Reset progress timeout because text is actively streaming
              lastText = currentText;
            }

            // Resolve when text is stable for 3s AND the page says streaming and continuations are done
            if (currentText && stableCount >= 6 && resp.done) {
              dump("AIAutomation: Response stable and done, resolving\n");
              done({ text: currentText, site });
              return;
            }

            // If the page says done but we need a bit more stability
            if (currentText && resp.done && stableCount >= 2) {
              dump(
                "AIAutomation: Response done flag set, resolving early\n"
              );
              done({ text: currentText, site });
              return;
            }
            
            if (noProgressIterations > 240) {
              dump("AIAutomation: TIMEOUT waiting for response\n");
              done({
                error: "Timeout waiting for response",
                lastSeen: lastText,
                site,
              });
            }
          } catch (e) {
            // Transient error (actor destroyed during navigation), keep going
            dump(
              "AIAutomation: Transient poll error (likely navigation): " +
                e.message +
                "\n"
            );
          }
        }, 500);
      }, settleMs); // site-aware settle time after prompt submit
    });
  },
};
