import { GarpConnection } from "./garp/GarpConnection.sys.mjs";
import { GarpFeature, GarpMessageType } from "./garp/GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./garp/GarpErrors.sys.mjs";
import { AIAutomationSessionManager } from "./sessions/AIAutomationSessionManager.sys.mjs";
import { GarpRequestManager } from "./requests/GarpRequestManager.sys.mjs";
import { ProviderRegistry } from "./providers/ProviderRegistry.sys.mjs";

const GARP_PORT = 9999;
const DEFAULT_REQUEST_RETENTION_MS = 10 * 60 * 1000;

function uuid() { return crypto.randomUUID(); }
function hex(bytes) { return [...bytes].map(b => b.toString(16).padStart(2, "0")).join(""); }

async function hmacSha256(secret, text) {
  const keyBytes = new TextEncoder().encode(secret);
  const data = new TextEncoder().encode(text);
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, data));
}

function constantTimeEqualHex(left, right) {
  const a = String(left || "").toLowerCase();
  const b = String(right || "").toLowerCase();
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export class AIAutomationService {
  constructor() {
    this.serverSocket = null;
    this.connections = new Set();
    this.providerRegistry = new ProviderRegistry();
    this.sessionManager = new AIAutomationSessionManager(this, this.providerRegistry);
    this.requestManager = new GarpRequestManager(this, this.sessionManager, this.providerRegistry);
    this.serverId = uuid();
    this.serverVersion = "1.0.0";
    const configuredSecret = Services.env.get("GARP_SECRET");
    this.authSecret = configuredSecret || this.generateStartupSecret();
    this.authEnabled = true;
    this.generatedAuthSecret = !configuredSecret;
    this.heartbeatTimer = null;
    this.requestRetentionTimer = null;
  }

  generateStartupSecret() {
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    return hex(bytes);
  }

  init() {
    if (this.serverSocket) return;
    try {
      this.serverSocket = Cc["@mozilla.org/network/server-socket;1"].createInstance(Ci.nsIServerSocket);
      this.serverSocket.init(GARP_PORT, true, -1);
      this.serverSocket.asyncListen(this);
      dump(`GARP/1.01: listening on 127.0.0.1:${GARP_PORT}\n`);
      if (this.generatedAuthSecret) dump(`GARP/1.01: generated startup authentication secret = ${this.authSecret}\n`);
    } catch (error) {
      this.serverSocket = null;
      Cu.reportError(`GARP/1.01 startup failed: ${error.message}`);
      throw error;
    }
  }

  shutdown() {
    if (this.heartbeatTimer) {
      this.heartbeatTimer = null;
    }
    for (const connection of [...this.connections]) connection.close();
    this.connections.clear();
    if (this.serverSocket) {
      try { this.serverSocket.close(); } catch (_) {}
      this.serverSocket = null;
    }
  }

  onSocketAccepted(_socket, transport) {
    const connection = new GarpConnection(transport, this);
    this.connections.add(connection);
  }

  onStopListening(_socket, _status) {
    this.serverSocket = null;
  }

  removeConnection(connection) {
    this.connections.delete(connection);
    this.requestManager.unsubscribeConnection(connection);
  }

  getTopWindow() {
    const { BrowserWindowTracker } = ChromeUtils.importESModule("resource:///modules/BrowserWindowTracker.sys.mjs");
    return BrowserWindowTracker.getTopWindow();
  }

  async handleGarpMessage(connection, decoded) {
    const message = decoded.message;
    const type = message.type;

    if (type === "hello") return this.handleHello(connection, message);
    if (type === "hello_auth") return this.handleHelloAuth(connection, message);

    if (!connection.authenticated) {
      throw new GarpError(GarpErrorCode.UNAUTHORIZED, "GARP authentication required", { state: "AUTHENTICATING" });
    }

    switch (type) {
      case "ping":
        connection.send(GarpMessageType.PONG, { state: "alive" });
        return;
      case "capabilities":
        connection.send(GarpMessageType.CAPABILITIES, {
          protocol: "GARP/1.01",
          features: [...GarpFeature],
          providers: this.providerRegistry.list(),
        });
        return;
      case "browser_status":
        connection.send(GarpMessageType.BROWSER_STATUS, this.browserStatus());
        return;
      case "list_tabs":
        this.sendResponse(connection, decoded, this.sessionManager.listTabs());
        return;
      case "open_tab":
        this.sendResponse(connection, decoded, this.sessionManager.openTab(message.payload?.url || "about:blank"));
        return;
      case "close_tab":
        this.sendResponse(connection, decoded, this.sessionManager.closeTab(message.payload?.tab_id ?? message.payload?.index));
        return;
      case "select_tab":
        this.sendResponse(connection, decoded, this.sessionManager.selectTab(message.payload?.tab_id ?? message.payload?.index));
        return;
      case "create_session":
        return this.handleCreateSession(connection, decoded);
      case "attach_session":
        return this.handleAttachSession(connection, decoded);
      case "detach_session":
        return this.handleSessionCommand(connection, decoded, "detach");
      case "close_session":
        return this.handleSessionCommand(connection, decoded, "close");
      case "reset_session":
        return this.handleSessionCommand(connection, decoded, "reset");
      case "prompt":
        return this.handlePrompt(connection, decoded);
      case "cancel_prompt":
        return this.handleCancel(connection, decoded);
      case "get_prompt_status":
        return this.handleGetPromptStatus(connection, decoded);
      case "get_response":
        return this.handleGetResponse(connection, decoded);
      case "subscribe_response":
        return this.handleSubscribe(connection, decoded);
      default:
        throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, `Unsupported GARP command: ${type}`);
    }
  }

  handleHello(connection, message) {
    if (connection.authState !== "CONNECTED") {
      throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "HELLO received in invalid state");
    }
    const payload = message.payload || {};
    const clientId = String(payload.client_id || "");
    const clientNonce = String(payload.nonce || "");
    if (!clientId || !clientNonce) throw new GarpError(GarpErrorCode.BAD_REQUEST, "HELLO requires client_id and nonce");
    connection.clientId = clientId;
    connection.clientNonce = clientNonce;
    connection.serverNonce = hex(crypto.getRandomValues(new Uint8Array(32)));
    connection.authState = "AUTHENTICATING";
    const challenge = {
      server_id: this.serverId,
      server_version: this.serverVersion,
      server_nonce: connection.serverNonce,
      auth: { algorithm: "HMAC-SHA256" },
    };
    connection.send("hello_challenge", challenge);
  }

  async handleHelloAuth(connection, message) {
    if (connection.authState !== "AUTHENTICATING") throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "HELLO_AUTH received in invalid state");
    const payload = message.payload || {};
    if (payload.client_id !== connection.clientId || payload.client_nonce !== connection.clientNonce || payload.server_nonce !== connection.serverNonce) {
      throw new GarpError(GarpErrorCode.UNAUTHORIZED, "GARP challenge identity mismatch");
    }
    const input = ["GARP/1.01", connection.clientId, connection.clientNonce, connection.serverNonce].join("|");
    const expected = hex(await hmacSha256(this.authSecret, input));
    if (!constantTimeEqualHex(expected, payload.proof)) {
      throw new GarpError(GarpErrorCode.UNAUTHORIZED, "GARP authentication failed");
    }
    connection.authenticated = true;
    connection.authState = "READY";
    connection.send("hello_ack", {
      server_id: this.serverId,
      server_version: this.serverVersion,
      browser: { name: "Firefox", version: Services.appinfo.version },
      features: [...GarpFeature],
    });
  }

  browserStatus() {
    const win = this.getTopWindow();
    return {
      state: win ? "READY" : "ERROR",
      browser: "Firefox",
      version: Services.appinfo.version,
      provider_count: this.providerRegistry.list().length,
      session_count: this.sessionManager.sessions.size,
    };
  }

  handleCreateSession(connection, decoded) {
    const payload = decoded.message.payload || {};
    const session = this.sessionManager.createSession(payload.provider, payload.tab_id ?? payload.tab_index ?? null);
    this.sendResponse(connection, decoded, session.snapshot());
    this.prepareSession(session).catch(error => this.emitSessionError(session, error));
  }

  handleAttachSession(connection, decoded) {
    const payload = decoded.message.payload || {};
    const session = this.sessionManager.attachSession(payload.session_id, payload.tab_id ?? payload.tab_index);
    this.sendResponse(connection, decoded, session.snapshot());
    this.prepareSession(session).catch(error => this.emitSessionError(session, error));
  }

  handleSessionCommand(connection, decoded, operation) {
    const sessionId = decoded.message.payload?.session_id || decoded.message.session_id;
    const session = operation === "detach" ? this.sessionManager.detachSession(sessionId) :
      operation === "close" ? (this.sessionManager.closeSession(sessionId), null) :
      this.sessionManager.resetSession(sessionId);
    this.sendResponse(connection, decoded, session ? session.snapshot() : { session_id: sessionId, state: "CLOSED" });
  }

  async prepareSession(session) {
    const result = await this.callChild(session, "PrepareSession", { provider: session.provider });
    if (result?.error) throw new GarpError(result.code || GarpErrorCode.DOM_UNSUPPORTED, result.error, { state: result.state || "ERROR" });
    session.inputState = result.input_state || (result.input_ready ? "READY" : "NOT_READY");
    if (result.authenticated === false) session.state = "AUTH_REQUIRED";
    else if (result.rate_limited) session.state = "RATE_LIMITED";
    else if (result.input_ready) session.state = "READY";
    else session.state = "PREPARING";
    this.broadcastSession(session, "session_ready", session.snapshot());
    return result;
  }

  async handlePrompt(connection, decoded) {
    const message = decoded.message;
    const sessionId = message.session_id || message.payload?.session_id;
    const requestId = message.request_id || decoded.request_id || uuid();
    const session = this.sessionManager.get(sessionId);
    const prompt = String(message.payload?.prompt?.text ?? "");
    if (!prompt) throw new GarpError(GarpErrorCode.BAD_REQUEST, "PROMPT requires payload.prompt.text");
    const options = message.payload?.options || {};
    const request = this.requestManager.startPrompt(connection, sessionId, requestId, prompt, options);
    connection.send(GarpMessageType.PROMPT_ACK, { state: "accepted" }, { request_id: request.requestId, session_id: request.sessionId });
  }

  handleCancel(connection, decoded) {
    const requestId = decoded.message.request_id || decoded.request_id;
    if (!requestId) throw new GarpError(GarpErrorCode.BAD_REQUEST, "CANCEL_PROMPT requires request_id");
    const request = this.requestManager.cancel(requestId, decoded.message.payload?.reason || "cancelled");
    connection.send(GarpMessageType.CANCEL_ACK, { state: request.state }, { request_id: request.requestId, session_id: request.sessionId });
  }

  handleGetPromptStatus(connection, decoded) {
    const requestId = decoded.message.request_id || decoded.message.payload?.request_id || decoded.request_id;
    if (!requestId) throw new GarpError(GarpErrorCode.BAD_REQUEST, "GET_PROMPT_STATUS requires request_id");
    const request = this.requestManager.get(requestId);
    this.sendResponse(connection, decoded, request.snapshot());
  }

  handleGetResponse(connection, decoded) {
    const requestId = decoded.message.request_id || decoded.request_id;
    const request = this.requestManager.get(requestId);
    if (!request.messageId) {
      connection.send("generation_progress", request.snapshot(), { request_id: request.requestId, session_id: request.sessionId });
      return;
    }
    this.sendResponse(connection, decoded, {
      request_id: request.requestId,
      state: request.state,
      message_id: request.messageId,
      content: request.text,
      page_generation: request.pageGeneration,
    });
  }

  handleSubscribe(connection, decoded) {
    const requestId = decoded.message.request_id || decoded.message.payload?.request_id || decoded.request_id;
    if (!requestId) throw new GarpError(GarpErrorCode.BAD_REQUEST, "SUBSCRIBE_RESPONSE requires request_id");
    const request = this.requestManager.get(requestId);
    this.requestManager.subscribe(requestId, connection);
    this.sendResponse(connection, decoded, { request_id: requestId, subscribed: true, state: request.state });
  }

  sendResponse(connection, decoded, payload) {
    connection.send("response", payload, {
      request_id: decoded.request_id || decoded.message.request_id || undefined,
      session_id: decoded.session_id || decoded.message.session_id || undefined,
    });
  }

  async callChild(session, operation, payload) {
    const tab = this.sessionManager.getTabForSession(session);
    const browser = tab.linkedBrowser;
    if (!browser?.browsingContext?.currentWindowGlobal) {
      throw new GarpError(GarpErrorCode.NAVIGATION_CHANGED, "Browser content is not ready", { retryable: true, state: "PREPARING" });
    }
    const actor = browser.browsingContext.currentWindowGlobal.getActor("AIAutomation");
    if (!actor) throw new GarpError(GarpErrorCode.DOM_UNSUPPORTED, "AIAutomation child actor unavailable");
    let generationChanged = false;
    if (session._lastActor && session._lastActor !== actor) {
      session.markPageGeneration(session.pageGeneration + 1, browser.currentURI.spec);
      generationChanged = true;
      this.broadcastSession(session, "navigation", { reason: "actor_replaced", page_generation: session.pageGeneration });
    }
    session._lastActor = actor;
    if (!generationChanged && session.pageURL && session.pageURL !== browser.currentURI.spec) {
      session.markPageGeneration(session.pageGeneration + 1, browser.currentURI.spec);
      generationChanged = true;
      this.broadcastSession(session, "navigation", { reason: "url_changed", page_generation: session.pageGeneration, url: browser.currentURI.spec });
    }
    session.pageURL = browser.currentURI.spec;
    return actor.sendQuery(`GARP:${operation}`, payload);
  }

  broadcastSession(session, type, payload) {
    for (const connection of this.connections) {
      if (!connection.authenticated) continue;
      connection.send(type, payload, { session_id: session.sessionId, page_generation: session.pageGeneration, timestamp: new Date().toISOString() });
    }
  }

  emitSessionError(session, error) {
    session.state = error?.state || "ERROR";
    this.broadcastSession(session, "provider_error", {
      code: error?.code || GarpErrorCode.INTERNAL_ERROR,
      message: error?.message || String(error),
    });
  }
}
