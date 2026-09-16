import { GarpConnection } from "./garp/GarpConnection.sys.mjs";
import {
  GARP_BASE_FEATURES,
  GARP_PROTOCOL,
  GARP_SEMANTIC_VERSION,
  GARP_SUPPORTED_EXTENSIONS,
  GARP_WIRE_VERSION,
  GarpMessageType,
} from "./garp/GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./garp/GarpErrors.sys.mjs";
import {
  assertNonce16,
  base64URLToBytes,
  buildTranscript,
  bytesToBase64URL,
  constantTimeEqualBytes,
  hmacSha256,
  negotiateFeatures,
  randomNonce16,
  validateAndCanonicaliseFeatures,
} from "./garp/GarpAuth.sys.mjs";
import { AIAutomationSessionManager } from "./sessions/AIAutomationSessionManager.sys.mjs";
import { GarpRequestManager } from "./requests/GarpRequestManager.sys.mjs";
import { ProviderRegistry } from "./providers/ProviderRegistry.sys.mjs";

const GARP_PORT = 9999;
const HANDSHAKE_TIMEOUT_MS = 10000;

function uuid() { return crypto.randomUUID(); }

function rawSecretFromEnv() {
  // §16.2: shared secret MUST contain at least 32 raw bytes. The environment
  // variable is interpreted as raw UTF-8 bytes unless the deployment says
  // otherwise. We require >= 32 bytes after encoding.
  const configured = Services.env.get("GARP_SECRET");
  if (configured) {
    const bytes = new TextEncoder().encode(configured);
    if (bytes.length < 32) {
      throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "GARP_SECRET must encode to at least 32 bytes");
    }
    return bytes;
  }
  // Development fallback: generate a random 32-byte secret and dump it once.
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  dump(`GARP/1.24: generated startup secret (base64url) = ${bytesToBase64URL(bytes)}\n`);
  return bytes;
}

export class AIAutomationService {
  constructor() {
    this.serverSocket = null;
    this.connections = new Set();

    this.providerRegistry = new ProviderRegistry();
    this.sessionManager = new AIAutomationSessionManager(this, this.providerRegistry);
    this.requestManager = new GarpRequestManager(this, this.sessionManager, this.providerRegistry);

    this.serverId = uuid();
    this.serverName = "FirefoxAIAutomation";
    this.serverVersion = "1.24.0";

    this.authSecretBytes = rawSecretFromEnv();

    // §19: replay-protection store. We keep an in-memory set for this build.
    // A production implementation MUST persist this across restarts and
    // disable the secret if state is lost.
    this.replayStore = new Set();

    this.heartbeatTimer = null;
    this.handshakeTimers = new WeakMap();
  }

  init() {
    if (this.serverSocket) return;
    try {
      this.serverSocket = Cc["@mozilla.org/network/server-socket;1"].createInstance(Ci.nsIServerSocket);
      this.serverSocket.init(GARP_PORT, true, -1);
      this.serverSocket.asyncListen(this);
      dump(`GARP/1.24: listening on 127.0.0.1:${GARP_PORT}\n`);
    } catch (error) {
      this.serverSocket = null;
      Cu.reportError(`GARP/1.24 startup failed: ${error.message}`);
      throw error;
    }
  }

  shutdown() {
    for (const c of [...this.connections]) c.close();
    this.connections.clear();
    if (this.serverSocket) {
      try { this.serverSocket.close(); } catch (_) {}
      this.serverSocket = null;
    }
  }

  onSocketAccepted(_socket, transport) {
    const connection = new GarpConnection(transport, this);
    this.connections.add(connection);
    const timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
    timer.initWithCallback(
      () => {
        if (!connection.authenticated && !connection.closed) {
          connection.fail(new GarpError(GarpErrorCode.HANDSHAKE_TIMEOUT, "handshake timeout"));
        }
      },
      HANDSHAKE_TIMEOUT_MS,
      Ci.nsITimer.TYPE_ONE_SHOT
    );
    this.handshakeTimers.set(connection, timer);
  }

  onStopListening() { this.serverSocket = null; }

  removeConnection(connection) {
    this.connections.delete(connection);
    this.requestManager.unsubscribeConnection(connection);
    const timer = this.handshakeTimers.get(connection);
    if (timer) { try { timer.cancel(); } catch (_) {} }
  }

  getTopWindow() {
    const { BrowserWindowTracker } = ChromeUtils.importESModule(
      "resource:///modules/BrowserWindowTracker.sys.mjs"
    );
    return BrowserWindowTracker.getTopWindow();
  }

  // -------------------------------------------------------------------------
  // Message dispatch
  // -------------------------------------------------------------------------

  async handleGarpMessage(connection, decoded) {
    const { type } = decoded;

    if (type === "HELLO") return this.handleHello(connection, decoded);
    if (type === "HELLO_AUTH") return this.handleHelloAuth(connection, decoded);

    if (!connection.authenticated) {
      throw Object.assign(
        new GarpError(GarpErrorCode.AUTH_REQUIRED, "connection not authenticated"),
        { requestId: decoded.requestId, sessionId: decoded.sessionId }
      );
    }

    // Keepalive bookkeeping (§101): any valid authenticated inbound frame updates
    // last_inbound_authenticated_time.
    connection.lastInboundAuthenticatedTime = Date.now();

    switch (type) {
      case "PING":                 return this.handlePing(connection, decoded);
      case "GET_CAPABILITIES":     return this.handleGetCapabilities(connection, decoded);
      case "CAPABILITIES":         return this.handlePeerCapabilities(connection, decoded);
      case "BROWSER_STATUS":       return; // client -> gateway: ignore / not used
      case "LIST_TABS":            return this.handleListTabs(connection, decoded);
      case "OPEN_TAB":             return this.handleOpenTab(connection, decoded);
      case "CLOSE_TAB":            return this.handleCloseTab(connection, decoded);
      case "SELECT_TAB":           return this.handleSelectTab(connection, decoded);
      case "CREATE_SESSION":       return this.handleCreateSession(connection, decoded);
      case "ATTACH_SESSION":       return this.handleAttachSession(connection, decoded);
      case "DETACH_SESSION":       return this.handleDetachSession(connection, decoded);
      case "CLOSE_SESSION":        return this.handleCloseSession(connection, decoded);
      case "RESET_SESSION":        return this.handleResetSession(connection, decoded);
      case "GET_SESSION":          return this.handleGetSession(connection, decoded);
      case "PROMPT":               return this.handlePrompt(connection, decoded);
      case "CANCEL_PROMPT":        return this.handleCancel(connection, decoded);
      case "GET_PROMPT_STATUS":    return this.handleGetPromptStatus(connection, decoded);
      case "GET_RESPONSE":         return this.handleGetResponse(connection, decoded);
      case "SUBSCRIBE_RESPONSE":   return this.handleSubscribe(connection, decoded);
      case "CONTINUE_PROMPT":      return this.handleContinuePrompt(connection, decoded);
      default:
        throw Object.assign(
          new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `unsupported command: ${type}`),
          { requestId: decoded.requestId, sessionId: decoded.sessionId }
        );
    }
  }

  // -------------------------------------------------------------------------
  // Handshake (§16–§17)
  // -------------------------------------------------------------------------

  handleHello(connection, decoded) {
    if (connection.state !== "NEW") {
      throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "HELLO in invalid state");
    }
    const p = decoded.payload || {};

    if (typeof p.client_name !== "string" || typeof p.client_version !== "string") {
      throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "HELLO requires client_name and client_version");
    }
    if (!Array.isArray(p.versions) || !p.versions.includes(GARP_SEMANTIC_VERSION)) {
      throw new GarpError(GarpErrorCode.UNSUPPORTED_VERSION, "client does not offer 1.24");
    }
    if (!Array.isArray(p.wire_versions) || !p.wire_versions.includes(GARP_WIRE_VERSION)) {
      throw new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, "client does not offer wire version 0x00");
    }

    const offered = validateAndCanonicaliseFeatures(p.features || []);
    const finalFeatures = negotiateFeatures(
      offered,
      [...GARP_BASE_FEATURES, ...GARP_SUPPORTED_EXTENSIONS]
    );

    const clientNonceBytes = assertNonce16(p.client_nonce, "client_nonce");
    const serverNonceBytes = randomNonce16();

    connection.state = "HELLO_RECEIVED";
    connection.clientName = p.client_name;
    connection.clientVersion = p.client_version;
    connection.clientNonceBytes = clientNonceBytes;
    connection.serverNonceBytes = serverNonceBytes;
    connection.offeredFeatures = offered.map(o => o.raw);
    connection.finalFeatures = finalFeatures;
    connection.requestId = decoded.requestId; // for later correlation

    connection.state = "CHALLENGE_SENT";
    connection.send("HELLO_CHALLENGE", {
      server_name: this.serverName,
      server_version: this.serverVersion,
      selected_version: GARP_SEMANTIC_VERSION,
      selected_wire_version: GARP_WIRE_VERSION,
      features: finalFeatures,
      server_nonce: bytesToBase64URL(serverNonceBytes),
    }, { request_id: decoded.requestId });
  }

  async handleHelloAuth(connection, decoded) {
    if (connection.state !== "CHALLENGE_SENT") {
      throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "HELLO_AUTH in invalid state");
    }
    const p = decoded.payload || {};
    if (typeof p.client_proof !== "string") {
      throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "HELLO_AUTH requires client_proof");
    }
    connection.state = "AUTH_VERIFYING";

    const transcript = buildTranscript({
      domain: "GARP/1.24/client-proof",
      clientNonceBytes: connection.clientNonceBytes,
      serverNonceBytes: connection.serverNonceBytes,
      selectedSemanticVersion: GARP_SEMANTIC_VERSION,
      selectedWireVersion: GARP_WIRE_VERSION,
      offeredFeatures: connection.offeredFeatures,
      finalFeatures: connection.finalFeatures,
      clientName: connection.clientName,
      clientVersion: connection.clientVersion,
      serverName: this.serverName,
      serverVersion: this.serverVersion,
    });

    const expected = await hmacSha256(this.authSecretBytes, transcript);

    let presented;
    try {
      presented = base64URLToBytes(p.client_proof);
    } catch (_) {
      throw new GarpError(GarpErrorCode.AUTH_FAILED, "invalid client_proof encoding");
    }

    if (presented.length !== 32 || !constantTimeEqualBytes(expected, presented)) {
      throw new GarpError(GarpErrorCode.AUTH_FAILED, "client proof mismatch");
    }

    // §19.2 replay detection.
    const transcriptDigestBytes = await crypto.subtle.digest("SHA-256", transcript);
    const replayKey = [...new Uint8Array(transcriptDigestBytes)]
      .map(b => b.toString(16).padStart(2, "0")).join("");
    if (this.replayStore.has(replayKey)) {
      throw new GarpError(GarpErrorCode.AUTH_REPLAY, "authentication replay detected");
    }
    this.replayStore.add(replayKey);

    // §17.4 server proof.
    const serverTranscript = buildTranscript({
      domain: "GARP/1.24/server-proof",
      clientNonceBytes: connection.clientNonceBytes,
      serverNonceBytes: connection.serverNonceBytes,
      selectedSemanticVersion: GARP_SEMANTIC_VERSION,
      selectedWireVersion: GARP_WIRE_VERSION,
      offeredFeatures: connection.offeredFeatures,
      finalFeatures: connection.finalFeatures,
      clientName: connection.clientName,
      clientVersion: connection.clientVersion,
      serverName: this.serverName,
      serverVersion: this.serverVersion,
    });
    const serverProof = await hmacSha256(this.authSecretBytes, serverTranscript);

    connection.state = "AUTHENTICATED_PENDING_ACK";
    connection.send("HELLO_ACK", {
      server_proof: bytesToBase64URL(serverProof),
      selected_version: GARP_SEMANTIC_VERSION,
      selected_wire_version: GARP_WIRE_VERSION,
      features: connection.finalFeatures,
    }, { request_id: decoded.requestId });

    connection.authenticated = true;
    connection.state = "AUTHENTICATED";
    connection.lastInboundAuthenticatedTime = Date.now();

    const timer = this.handshakeTimers.get(connection);
    if (timer) { try { timer.cancel(); } catch (_) {} }

    // §21 + §115: CAPABILITIES and BROWSER_STATUS emitted immediately.
    this.emitCapabilities(connection);
    this.emitBrowserStatus(connection);
  }

  // -------------------------------------------------------------------------
  // Capabilities
  // -------------------------------------------------------------------------

  buildCapabilitiesPayload() {
    return {
      protocol: GARP_SEMANTIC_VERSION,
      wire_version: GARP_WIRE_VERSION,
      limits: {
        handshake_timeout_ms: String(HANDSHAKE_TIMEOUT_MS),
        max_payload_bytes: 16777216,
        max_prompt_size: 1048576,
        max_response_size: 16777216,
        max_outstanding_requests: 128,
        max_queued_events: 8192,
        max_event_history_memory_mb: 64,
        max_generation_buffer_mb: 32,
        response_retention_ms: "86400000",
        continuation_wait_ms: "300000",
        recovery_deadline_ms: "300000",
        max_error_details_bytes: 65536,
        max_diagnostic_details_bytes: 65536,
      },
      keepalive: {
        enabled: false,
        idle_timeout_ms: "30000",
        interval_ms: "10000",
      },
      providers: this.providerRegistry.capabilityEntries(),
      extensions: GARP_SUPPORTED_EXTENSIONS.map(name => ({ name, version: "1.0" })),
    };
  }

  emitCapabilities(connection) {
    // §21: connection-scoped, unsolicited.
    connection.send("CAPABILITIES", this.buildCapabilitiesPayload(), {});
  }

  handleGetCapabilities(connection, decoded) {
    this.sendResponse(connection, decoded, {
      success: true,
      ...this.buildCapabilitiesPayload(),
    });
  }

  handlePeerCapabilities(connection, decoded) {
    // Client is announcing its capabilities. Mark handshake limit as lifted
    // for our outbound direction (§6.5 is per-direction).
    connection.peerOfferedCapabilities = true;
    const advertised = Number(decoded.payload?.limits?.max_payload_bytes);
    if (Number.isFinite(advertised) && advertised > 0) {
      connection.ourEffectivePayloadLimit = Math.min(advertised, 0xFFFFFFFF);
    }
  }

  // -------------------------------------------------------------------------
  // Browser status
  // -------------------------------------------------------------------------

  emitBrowserStatus(connection) {
    const win = this.getTopWindow();
    const tabs = win ? win.gBrowser.tabs : [];
    const active = win ? win.gBrowser.selectedTab : null;
    let activeId = null;
    if (active) {
      try { activeId = this.sessionManager.getStableTabId(active); } catch (_) {}
    }
    connection.send("BROWSER_STATUS", {
      state: win ? "READY" : "FAILED",
      active_tab_id: activeId,
    }, {});
  }

  // -------------------------------------------------------------------------
  // PING / PONG
  // -------------------------------------------------------------------------

  handlePing(connection, decoded) {
    // §99: a PING is answered by a normal RESPONSE, not by a PONG.
    this.sendResponse(connection, decoded, { success: true });
  }

  // -------------------------------------------------------------------------
  // Tabs
  // -------------------------------------------------------------------------

  handleListTabs(connection, decoded) {
    this.sendResponse(connection, decoded, {
      success: true,
      tabs: this.sessionManager.listTabs(),
    });
  }

  handleOpenTab(connection, decoded) {
    const url = String(decoded.payload?.url || "");
    if (!/^https?:\/\//i.test(url)) {
      throw Object.assign(
        new GarpError(GarpErrorCode.INVALID_ARGUMENT, "OPEN_TAB requires http(s) URL"),
        { requestId: decoded.requestId, sessionId: null }
      );
    }
    const result = this.sessionManager.openTab(url);
    this.sendResponse(connection, decoded, { success: true, ...result });
  }

  handleCloseTab(connection, decoded) {
    const result = this.sessionManager.closeTab(decoded.payload?.tab_id);
    this.sendResponse(connection, decoded, { success: true, ...result });
  }

  handleSelectTab(connection, decoded) {
    const result = this.sessionManager.selectTab(decoded.payload?.tab_id);
    this.sendResponse(connection, decoded, { success: true, ...result });
  }

  // -------------------------------------------------------------------------
  // Sessions
  // -------------------------------------------------------------------------

  handleCreateSession(connection, decoded) {
    const payload = decoded.payload || {};
    const session = this.sessionManager.createSession(
      payload.provider,
      payload.tab_id ?? null
    );
    // §35: CREATE_SESSION response is connection-scoped.
    this.sendResponse(connection, decoded, {
      success: true,
      session_id: session.sessionId,
      state: session.state,
    });
    this.prepareSession(session).catch(err => this.emitSessionError(session, err));
  }

  handleAttachSession(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    session.attachToConnection(connection);
    this.sendResponse(connection, decoded, {
      success: true,
      session_id: session.sessionId,
      state: session.state,
      provider: session.provider,
      tab_id: session.tabId,
      url: session.pageURL,
      page_generation: String(session.pageGeneration),
    });
  }

  handleDetachSession(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    session.detachFromConnection(connection);
    this.sendResponse(connection, decoded, { success: true });
  }

  handleCloseSession(connection, decoded) {
    const sessionId = decoded.sessionId;
    this.sessionManager.closeSession(sessionId);
    this.sendResponse(connection, decoded, { success: true });
  }

  handleResetSession(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    if (session.state === "CLOSED") {
      throw Object.assign(
        new GarpError(GarpErrorCode.SESSION_CLOSED, "session closed"),
        { requestId: decoded.requestId, sessionId: session.sessionId }
      );
    }
    session.reset();
    this.sendResponse(connection, decoded, {
      success: true,
      session_id: session.sessionId,
      state: session.state,
    });
    this.prepareSession(session).catch(err => this.emitSessionError(session, err));
  }

  handleGetSession(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    this.sendResponse(connection, decoded, {
      success: true,
      session_id: session.sessionId,
      state: session.state,
      provider: session.provider,
      tab_id: session.tabId,
      url: session.pageURL,
      page_generation: String(session.pageGeneration),
      active_prompt_request_id: session.activeRequestId,
    });
  }

  async prepareSession(session) {
    let result;
    try {
      result = await this.callChild(session, "PrepareSession", { provider: session.provider });
    } catch (error) {
      if (error?.code === GarpErrorCode.NAVIGATION_DRIFT || error?.code === GarpErrorCode.STALE_ACTOR) {
        // Retry once after reacquiring actor.
        result = await this.callChild(session, "PrepareSession", { provider: session.provider });
      } else {
        throw error;
      }
    }
    if (result?.error) {
      session.state = result.state || "FAILED";
      throw new GarpError(result.code || GarpErrorCode.PROVIDER_ERROR, result.error, {
        provider: session.provider,
        state: session.state,
      });
    }
    session.inputState = result.input_state || (result.input_ready ? "READY" : "NOT_READY");
    if (result.authenticated === false) session.state = "AUTH_REQUIRED";
    else if (result.rate_limited) session.state = "RATE_LIMITED";
    else if (result.input_ready) session.state = "READY";
    else session.state = "PREPARING";

    if (session.state === "READY") {
      this.emitSessionEvent(session, "SESSION_READY", {
        provider: session.provider,
        tab_id: session.tabId,
        url: session.pageURL,
        page_generation: String(session.pageGeneration),
      });
    }
  }

  // -------------------------------------------------------------------------
  // Prompts
  // -------------------------------------------------------------------------

  handlePrompt(connection, decoded) {
    const payload = decoded.payload || {};
    const promptText = String(payload.prompt ?? "");
    if (promptText.length === 0) {
      throw Object.assign(
        new GarpError(GarpErrorCode.INVALID_ARGUMENT, "PROMPT requires prompt"),
        { requestId: decoded.requestId, sessionId: decoded.sessionId }
      );
    }
    const options = payload.options || {};
    const request = this.requestManager.startPrompt(
      connection,
      decoded.sessionId,
      decoded.requestId,
      promptText,
      options
    );
    this.sendResponse(connection, decoded, {
      success: true,
      command_state: "ACCEPTED",
      prompt_state: request.promptState,
    });
  }

  handleCancel(connection, decoded) {
    const promptRequestId = decoded.payload?.prompt_request_id;
    if (!promptRequestId) {
      throw Object.assign(
        new GarpError(GarpErrorCode.INVALID_ARGUMENT, "CANCEL_PROMPT requires prompt_request_id"),
        { requestId: decoded.requestId, sessionId: decoded.sessionId }
      );
    }
    const session = this.sessionManager.get(decoded.sessionId);
    const request = this.requestManager.getForSession(session, promptRequestId);
    this.requestManager.cancel(request);
    this.sendResponse(connection, decoded, {
      success: true,
      command_state: "ACCEPTED",
    });
  }

  handleGetPromptStatus(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    const request = this.requestManager.getForSession(session, decoded.payload?.prompt_request_id);
    this.sendResponse(connection, decoded, {
      success: true,
      prompt_request_id: request.requestId,
      state: request.promptState,
      page_generation: String(request.pageGeneration),
    });
  }

  handleGetResponse(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    const request = this.requestManager.getForSession(session, decoded.payload?.prompt_request_id);

    if (!request.isTerminal()) {
      throw Object.assign(
        new GarpError(GarpErrorCode.RESPONSE_NOT_READY, "response not terminally available"),
        { requestId: decoded.requestId, sessionId: session.sessionId }
      );
    }

    const payload = {
      success: true,
      state: request.promptState,
    };
    if (request.promptState === "COMPLETED") {
      payload.response = request.text;
    } else if (request.promptState === "CANCELLED") {
      payload.partial = request.hasCommittedContent();
      payload.response = payload.partial ? request.text : null;
    } else {
      payload.partial = request.hasCommittedContent();
      payload.response = payload.partial ? request.text : null;
      if (request.error) payload.error = { code: request.error.code, message: request.error.message };
    }
    this.sendResponse(connection, decoded, payload);
  }

  handleSubscribe(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    const request = this.requestManager.getForSession(session, decoded.payload?.prompt_request_id);
    this.requestManager.subscribe(request, connection);
    this.sendResponse(connection, decoded, { success: true });
  }

  handleContinuePrompt(connection, decoded) {
    const session = this.sessionManager.get(decoded.sessionId);
    const request = this.requestManager.getForSession(session, decoded.payload?.prompt_request_id);
    this.requestManager.continueExplicit(request);
    this.sendResponse(connection, decoded, { success: true, command_state: "ACCEPTED" });
  }

  // -------------------------------------------------------------------------
  // Event emission
  // -------------------------------------------------------------------------

  emitSessionEvent(session, type, payload) {
    const sequence = session.nextSequence();
    const subscribers = session.subscribers;
    for (const conn of subscribers) {
      if (!conn.authenticated) continue;
      conn.send(type, payload, {
        request_id: null,         // §11.4 global correlation rule
        session_id: session.sessionId,
        sequence: String(sequence),
      });
    }
  }

  emitSessionError(session, error) {
    session.state = error?.state || "FAILED";
    this.emitSessionEvent(session, "PROVIDER_ERROR", {
      provider: session.provider,
      code: error?.code || GarpErrorCode.PROVIDER_ERROR,
      message: error?.message || String(error),
      retryable: !!error?.retryable,
      prompt_request_id: session.activeRequestId ?? null,
      page_generation: String(session.pageGeneration),
    });
  }

  // -------------------------------------------------------------------------
  // Response helper
  // -------------------------------------------------------------------------

  sendResponse(connection, decoded, payload) {
    connection.send("RESPONSE", payload, {
      request_id: decoded.requestId,
      session_id: decoded.sessionId ?? null,
    });
  }

  // -------------------------------------------------------------------------
  // Child actor bridge
  // -------------------------------------------------------------------------

  async callChild(session, operation, payload) {
    const tab = this.sessionManager.getTabForSession(session);
    const browser = tab.linkedBrowser;
    const wg = browser?.browsingContext?.currentWindowGlobal;
    if (!wg) {
      throw Object.assign(
        new GarpError(GarpErrorCode.NAVIGATION_DRIFT, "browser content not ready", { retryable: true }),
        { state: "RECOVERING" }
      );
    }
    const actor = wg.getActor("AIAutomation");
    if (!actor) {
      throw Object.assign(
        new GarpError(GarpErrorCode.STALE_ACTOR, "child actor unavailable", { retryable: true }),
        { state: "RECOVERING" }
      );
    }

    if (session._lastActor && session._lastActor !== actor) {
      session.incrementPageGeneration(browser.currentURI.spec);
      this.emitSessionEvent(session, "NAVIGATION", {
        page_generation: String(session.pageGeneration),
        url: browser.currentURI.spec,
      });
    }
    session._lastActor = actor;
    session.pageURL = browser.currentURI.spec;

    const result = await actor.sendQuery(`GARP:${operation}`, {
      ...payload,
      _fencing: {
        session_id: session.sessionId,
        page_generation: String(session.pageGeneration),
        actor_instance: session.actorInstance,
        provider: session.provider,
      },
    });
    return result;
  }
}