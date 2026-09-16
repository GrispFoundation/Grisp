import {
  GarpConnectionScopedTypes,
  GarpMessageType,
  GarpFeature,
  GARP_PROTOCOL,
  GARP_SEMANTIC_VERSION,
  GARP_WIRE_VERSION,
  GARP_APPLICATION_LIMIT_DEFAULT,
  GARP_HANDSHAKE_TIMEOUT_MS,
  GARP_DEFAULT_RESPONSE_RETENTION_MS,
  GARP_DEFAULT_RECOVERY_DEADLINE_MS,
} from "./garp/GarpRegistry.sys.mjs";
import { GarpConnection } from "./garp/GarpConnection.sys.mjs";
import { GarpReplayStore } from "./garp/GarpReplayStore.sys.mjs";
import { GarpError, GarpErrorCode } from "./garp/GarpErrors.sys.mjs";
import {
  base64UrlDecode,
  base64UrlEncode,
  constantTimeEqualBytes,
  encodeTranscript,
  encodeTranscriptCore,
  hmacSha256,
  monotonicNow,
  sha256,
  sortedUtf8,
  textEncoder,
  uuid,
} from "./garp/GarpUtil.sys.mjs";
import { validateMessagePayload, validateEnvelope, capabilitiesObject } from "./garp/GarpSchema.sys.mjs";
import { AIAutomationSessionManager } from "./sessions/AIAutomationSessionManager.sys.mjs";
import { GarpRequestManager } from "./requests/GarpRequestManager.sys.mjs";
import { ProviderRegistry } from "./providers/ProviderRegistry.sys.mjs";

const GARP_PORT = 9999;

function readConfiguredSecret() {
  const value = Services.env.get("GARP_SECRET");
  if (!value) throw new GarpError(GarpErrorCode.AUTH_FAILED, "GARP_SECRET is required; GARP/1.24 does not generate or persist a deployment secret");
  const bytes = textEncoder.encode(value);
  if (bytes.length < 32) throw new GarpError(GarpErrorCode.AUTH_FAILED, "GARP_SECRET must encode to at least 32 raw bytes");
  return bytes;
}

export class AIAutomationService {
  constructor() {
    this.serverSocket = null;
    this.connections = new Set();
    this.providerRegistry = new ProviderRegistry();
    this.sessionManager = new AIAutomationSessionManager(this, this.providerRegistry);
    this.requestManager = new GarpRequestManager(this, this.sessionManager, this.providerRegistry);
    this.replayStore = new GarpReplayStore();
    this.serverId = uuid();
    this.serverName = "GarpGateway";
    this.serverVersion = "1.24.0";
    this.authSecret = null;
    this.authDisabled = false;
    this.capabilities = capabilitiesObject(this.providerRegistry);
    this.browserStatus = null;
    this.pruneTimer = null;
    this.statusTimer = null;
    this.initializing = false;
  }

  async initializeSecurityState() {
    this.authSecret = readConfiguredSecret();
    await this.replayStore.load();
    if (!this.replayStore.replayStateAvailable) {
      this.authDisabled = true;
      dump("GARP/1.24: authentication replay state unavailable; configured secret is disabled until deployment rotates it.\n");
    }
  }

  init() {
    if (this.serverSocket || this.initializing) return;
    this.initializing = true;
    this.initializeSecurityState().then(() => {
      this.serverSocket = Cc["@mozilla.org/network/server-socket;1"].createInstance(Ci.nsIServerSocket);
      try {
        this.serverSocket.init(GARP_PORT, true, -1);
        this.serverSocket.asyncListen(this);
        dump(`GARP/1.24: listening on 127.0.0.1:${GARP_PORT}\n`);
        this.pruneTimer = setInterval(() => this.requestManager.prune(Number(this.capabilities.limits.response_retention_ms)), 60000);
        this.statusTimer = setInterval(() => this.updateBrowserStatus(), 500);
        this.updateBrowserStatus(true);
      } catch (error) {
        this.serverSocket = null;
        Cu.reportError(`GARP/1.24 startup failed: ${error}`);
      } finally {
        this.initializing = false;
      }
    }).catch(error => {
      this.initializing = false;
      Cu.reportError(`GARP/1.24 security initialization failed: ${error}`);
    });
  }

  shutdown() {
    try { clearInterval(this.pruneTimer); } catch (_) {}
    try { clearInterval(this.statusTimer); } catch (_) {}
    this.pruneTimer = null;
    this.statusTimer = null;
    for (const connection of [...this.connections]) connection.close();
    this.connections.clear();
    for (const session of this.sessionManager.sessions.values()) session.state = "CLOSED";
    if (this.serverSocket) { try { this.serverSocket.close(); } catch (_) {} this.serverSocket = null; }
  }

  onSocketAccepted(_socket, transport) { this.connections.add(new GarpConnection(transport, this)); }
  onStopListening(_socket, _status) { this.serverSocket = null; }
  removeConnection(connection) {
    this.connections.delete(connection);
    this.requestManager.unsubscribeConnection(connection);
    for (const session of this.sessionManager.sessions.values()) if (session.ownerConnection === connection) session.ownerConnection = null;
  }

  getTopWindow() {
    const { BrowserWindowTracker } = ChromeUtils.importESModule("resource:///modules/BrowserWindowTracker.sys.mjs");
    return BrowserWindowTracker.getTopWindow();
  }

  updateBrowserStatus(force = false) {
    const win = this.getTopWindow();
    const activeTab = win?.gBrowser?.selectedTab;
    const activeTabId = activeTab ? this.sessionManager.getStableTabId(activeTab) : null;
    const next = { state: win ? "READY" : "FAILED", active_tab_id: activeTabId };
    const changed = !this.browserStatus || JSON.stringify(this.browserStatus) !== JSON.stringify(next);
    this.browserStatus = next;
    if (!force && !changed) return;
    for (const connection of this.connections) {
      if (connection.authenticated) {
        connection.send("BROWSER_STATUS", next, { request_id: null, session_id: null, sequence: null });
      }
    }
  }

  browserStatusPayload() {
    this.updateBrowserStatus(false);
    return this.browserStatus || { state: "FAILED", active_tab_id: null };
  }

  emitInitialBrowserStatus(connection) {
    const payload = this.browserStatusPayload();
    connection.send("BROWSER_STATUS", payload, { request_id: null, session_id: null, sequence: null });
  }

  localFeatures() { return sortedUtf8(GarpFeature); }

  negotiateFeatures(offered) {
    const supported = new Set(GarpFeature);
    const final = [];
    for (const raw of offered) {
      const required = raw.startsWith("!");
      const name = required ? raw.slice(1) : raw;
      if (supported.has(name)) final.push(`${required ? "!" : ""}${name}`);
      else if (required) throw new GarpError(GarpErrorCode.UNSUPPORTED_FEATURE, `Required feature unsupported: ${name}`);
    }
    return sortedUtf8(final);
  }

  async handleGarpMessage(connection, decoded) {
    const message = decoded.message;
    const type = decoded.type;

    if (type === "HELLO") return this.handleHello(connection, decoded);
    if (type === "HELLO_AUTH") return this.handleHelloAuth(connection, decoded);

    if (type === "CAPABILITIES") {
      if (!connection.authenticated) throw new GarpError(GarpErrorCode.AUTH_REQUIRED, "Authentication required");
      validateMessagePayload("CAPABILITIES", message.payload);
      connection.setPeerCapabilities(message.payload);
      return;
    }

    if (type === "PONG") {
      if (!connection.negotiatedFeatures.includes("ext-pong")) throw new GarpError(GarpErrorCode.UNSUPPORTED_FEATURE, "PONG extension not negotiated");
      return;
    }

    if (!connection.authenticated) throw new GarpError(GarpErrorCode.AUTH_REQUIRED, "Authentication required");

    switch (type) {
      case "PING": connection.sendResponse(decoded.request_id, null, { success: true }); break;
      case "GET_CAPABILITIES": connection.sendResponse(decoded.request_id, null, { success: true, ...this.capabilities }); break;
      case "BROWSER_STATUS": throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, "BROWSER_STATUS is an event, not a command");
      case "LIST_TABS": connection.sendResponse(decoded.request_id, null, { success: true, tabs: this.sessionManager.listTabs() }); this.updateBrowserStatus(); break;
      case "OPEN_TAB": connection.sendResponse(decoded.request_id, null, { success: true, ...this.sessionManager.openTab(message.payload.url) }); this.updateBrowserStatus(); break;
      case "CLOSE_TAB": connection.sendResponse(decoded.request_id, null, this.sessionManager.closeTab(message.payload.tab_id)); this.updateBrowserStatus(); break;
      case "SELECT_TAB": connection.sendResponse(decoded.request_id, null, this.sessionManager.selectTab(message.payload.tab_id)); this.updateBrowserStatus(); break;
      case "CREATE_SESSION": await this.handleCreateSession(connection, decoded); break;
      case "ATTACH_SESSION": await this.handleAttachSession(connection, decoded); break;
      case "DETACH_SESSION": await this.handleSessionCommand(connection, decoded, "detach"); break;
      case "CLOSE_SESSION": await this.handleSessionCommand(connection, decoded, "close"); break;
      case "RESET_SESSION": await this.handleSessionCommand(connection, decoded, "reset"); break;
      case "GET_SESSION": await this.handleGetSession(connection, decoded); break;
      case "PROMPT": await this.handlePrompt(connection, decoded); break;
      case "CANCEL_PROMPT": await this.handleCancel(connection, decoded); break;
      case "GET_PROMPT_STATUS": await this.handleGetPromptStatus(connection, decoded); break;
      case "GET_RESPONSE": await this.handleGetResponse(connection, decoded); break;
      case "SUBSCRIBE_RESPONSE": await this.handleSubscribe(connection, decoded); break;
      case "CONTINUE_PROMPT": await this.handleContinue(connection, decoded); break;
      case "GET_EVENTS": await this.handleGetEvents(connection, decoded); break;
      default: throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `Unsupported GARP message type: ${type}`);
    }
  }

  async handleHello(connection, decoded) {
    if (this.authDisabled) throw new GarpError(GarpErrorCode.AUTH_FAILED, "Authentication is disabled because replay state cannot be trusted");
    if (connection.authState !== "NEW") throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "HELLO received in invalid connection state");
    const payload = decoded.message.payload;
    const clientNonce = base64UrlDecode(payload.client_nonce, 16);
    const finalFeatures = this.negotiateFeatures(payload.features);
    connection.clientName = payload.client_name;
    connection.clientVersion = payload.client_version;
    connection.clientNonce = clientNonce;
    connection.offeredFeatures = sortedUtf8(payload.features);
    connection.serverNonce = crypto.getRandomValues(new Uint8Array(16));
    connection.negotiatedFeatures = finalFeatures;
    connection.authState = "CHALLENGE_SENT";
    connection.handshakeRequestId = decoded.request_id;
    connection.serverChallenge = {
      server_name: this.serverName,
      server_version: this.serverVersion,
      selected_version: GARP_SEMANTIC_VERSION,
      selected_wire_version: GARP_WIRE_VERSION,
      features: finalFeatures,
      server_nonce: base64UrlEncode(connection.serverNonce),
    };
    connection.send("HELLO_CHALLENGE", connection.serverChallenge, { request_id: decoded.request_id, session_id: null, sequence: null });
  }

  async handleHelloAuth(connection, decoded) {
    if (connection.authState !== "CHALLENGE_SENT" || decoded.request_id !== connection.handshakeRequestId) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "HELLO_AUTH received outside active handshake transaction");
    connection.authState = "AUTH_VERIFYING";
    const proof = base64UrlDecode(decoded.message.payload.client_proof, 32);
    const transcript = encodeTranscript(`${GARP_PROTOCOL}/client-proof`, connection.clientNonce, connection.serverNonce, GARP_SEMANTIC_VERSION, GARP_WIRE_VERSION, connection.offeredFeatures, connection.negotiatedFeatures, connection.clientName, connection.clientVersion, this.serverName, this.serverVersion);
    const key = await connection.replayKey();
    if (await this.replayStore.has(key)) throw new GarpError(GarpErrorCode.AUTH_REPLAY, "Authentication transcript has already been used");
    const expected = await hmacSha256(this.authSecret, transcript);
    if (!constantTimeEqualBytes(expected, proof)) throw new GarpError(GarpErrorCode.AUTH_FAILED, "Client authentication proof failed");
    await this.replayStore.remember(key);
    connection.authState = "AUTHENTICATED_PENDING_ACK";
    const serverTranscript = encodeTranscript(`${GARP_PROTOCOL}/server-proof`, connection.clientNonce, connection.serverNonce, GARP_SEMANTIC_VERSION, GARP_WIRE_VERSION, connection.offeredFeatures, connection.negotiatedFeatures, connection.clientName, connection.clientVersion, this.serverName, this.serverVersion);
    const serverProof = await hmacSha256(this.authSecret, serverTranscript);
    connection.send("HELLO_ACK", { server_proof: base64UrlEncode(serverProof), selected_version: GARP_SEMANTIC_VERSION, selected_wire_version: GARP_WIRE_VERSION, features: connection.negotiatedFeatures }, { request_id: decoded.request_id, session_id: null, sequence: null, isCommandResponse: true });
    connection.authenticated = true;
    connection.authState = "AUTHENTICATED";
    // CAPABILITIES and BROWSER_STATUS are deliberately emitted only after HELLO_ACK is committed.
    connection.send("CAPABILITIES", this.capabilities, { request_id: null, session_id: null, sequence: null });
    connection.send("BROWSER_STATUS", this.browserStatusPayload(), { request_id: null, session_id: null, sequence: null });
  }

  async handleCreateSession(connection, decoded) {
    const session = this.sessionManager.createSession(decoded.message.payload.provider, decoded.message.payload.tab_id ?? null);
    session.ownerConnection = connection;
    connection.sendResponse(decoded.request_id, null, { success: true, session_id: session.sessionId, state: "PREPARING" });
    this.prepareSession(session).catch(error => this.failSessionPreparation(session, error));
  }

  async handleAttachSession(connection, decoded) {
    const session = this.sessionManager.attachSession(decoded.session_id, connection);
    connection.sendResponse(decoded.request_id, session.sessionId, { success: true, ...session.snapshot(), state: session.state === "CREATED" ? "PREPARING" : session.state });
    if (session.state === "PREPARING" || session.state === "AUTH_REQUIRED" || session.state === "RATE_LIMITED") this.prepareSession(session).catch(error => this.failSessionPreparation(session, error));
  }

  async handleSessionCommand(connection, decoded, operation) {
    const session = this.sessionManager.get(decoded.session_id);
    if (session.ownerConnection && session.ownerConnection !== connection) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
    let result;
    if (operation === "detach") result = this.sessionManager.detachSession(session.sessionId, connection);
    else if (operation === "close") {
      await this.requestManager.abortForSessionReset(session, "SESSION_CLOSE");
      result = this.sessionManager.closeSession(session.sessionId);
    } else {
      await this.requestManager.abortForSessionReset(session, "SESSION_RESET");
      result = this.sessionManager.resetSession(session.sessionId, connection);
      this.commitSessionEvent(session, "SESSION_CHANGED", { changed: ["page_generation"], page_generation: String(session.pageGeneration) });
    }
    connection.sendResponse(decoded.request_id, decoded.session_id, { success: true, ...(operation === "close" || operation === "detach" ? {} : { session_id: result.sessionId, state: result.state }) });
  }

  async handleGetSession(connection, decoded) {
    const session = this.sessionManager.get(decoded.session_id);
    connection.sendResponse(decoded.request_id, session.sessionId, { success: true, ...session.snapshot() });
  }

  async prepareSession(session) {
    try {
      const result = await this.callChild(session, "PrepareSession", { provider: session.provider, prompt_request_id: null });
      if (result.error) throw this.errorFromChild(result);
      if (result.provider && result.provider !== session.provider) this.applyProviderChange(session, result.provider, result.authoritative_fencing);
      session.inputState = result.input_state || (result.input_ready ? "READY" : "NOT_READY");
      if (result.authenticated === false) { session.state = "AUTH_REQUIRED"; this.commitSessionEvent(session, "PROVIDER_AUTH_REQUIRED", { provider: session.provider, reason: "LOGIN_REQUIRED", page_generation: String(session.pageGeneration) }); }
      else if (result.rate_limited) session.state = "RATE_LIMITED";
      else if (result.input_ready) session.state = "READY";
      else session.state = "PREPARING";
      this.commitSessionEvent(session, "SESSION_READY", { provider: session.provider, tab_id: session.tabId, url: result.url || session.pageURL, page_generation: String(session.pageGeneration) });
    } catch (error) { throw error; }
  }

  failSessionPreparation(session, error) {
    if (session.state === "CLOSED") return;
    session.state = error?.code === GarpErrorCode.PROVIDER_AUTH_REQUIRED ? "AUTH_REQUIRED" : error?.code === GarpErrorCode.PROVIDER_RATE_LIMITED ? "RATE_LIMITED" : "FAILED";
    this.commitSessionEvent(session, "DIAGNOSTIC", { level: "ERROR", stage: "SESSION", code: error?.code || GarpErrorCode.PROVIDER_ERROR, message: error?.message || String(error), details: {}, actor_instance: session.actorInstance || uuid() });
  }

  errorFromChild(result) { return new GarpError(result.code || GarpErrorCode.PROVIDER_ERROR, result.error || "Provider operation failed"); }

  async handlePrompt(connection, decoded) {
    const session = this.sessionManager.get(decoded.session_id);
    if (session.ownerConnection && session.ownerConnection !== connection) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
    const request = this.requestManager.startPrompt(connection, decoded.session_id, decoded.request_id, decoded.message.payload.prompt, decoded.message.payload.options);
    connection.sendResponse(decoded.request_id, session.sessionId, { success: true, command_state: "ACCEPTED", prompt_state: request.state });
  }

  async handleCancel(connection, decoded) {
    const request = await this.requestManager.cancel(connection, decoded.session_id, decoded.message.payload.prompt_request_id);
    connection.sendResponse(decoded.request_id, decoded.session_id, { success: true, command_state: "ACCEPTED" });
  }

  async handleContinue(connection, decoded) {
    await this.requestManager.continuePrompt(connection, decoded.session_id, decoded.message.payload.prompt_request_id);
    connection.sendResponse(decoded.request_id, decoded.session_id, { success: true, command_state: "ACCEPTED" });
  }

  async handleGetPromptStatus(connection, decoded) {
    const request = this.requestManager.getForSession(decoded.session_id, decoded.message.payload.prompt_request_id);
    connection.sendResponse(decoded.request_id, decoded.session_id, request.snapshot());
  }

  async handleGetResponse(connection, decoded) {
    const request = this.requestManager.getForSession(decoded.session_id, decoded.message.payload.prompt_request_id);
    connection.sendResponse(decoded.request_id, decoded.session_id, this.requestManager.getResponse(request));
  }

  async handleSubscribe(connection, decoded) {
    const request = this.requestManager.subscribe(decoded.message.payload.prompt_request_id, connection);
    connection.sendResponse(decoded.request_id, decoded.session_id, { success: true });
  }

  async handleGetEvents(connection, decoded) {
    if (!connection.negotiatedFeatures.includes("ext-replay-store")) throw new GarpError(GarpErrorCode.UNSUPPORTED_FEATURE, "ext-replay-store is not negotiated");
    const session = this.sessionManager.get(decoded.session_id);
    const from = BigInt(decoded.message.payload.from_sequence);
    const maxEvents = decoded.message.payload.max_events;
    const snapshot = session.eventHistory.map(event => structuredClone(event));
    const currentLast = session.lastSequence();
    if (from > currentLast + 1n) throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "from_sequence is beyond the current sequence plus one");
    if (from < session.oldestSequence()) throw new GarpError(GarpErrorCode.EVENT_HISTORY_EXPIRED, "Requested event history has expired");
    const events = snapshot.filter(event => BigInt(event.sequence) >= from && BigInt(event.sequence) <= currentLast).slice(0, maxEvents);
    const next = events.length ? BigInt(events[events.length - 1].sequence) + 1n : from;
    const complete = events.length ? BigInt(events[events.length - 1].sequence) === currentLast : from === currentLast + 1n;
    connection.sendResponse(decoded.request_id, session.sessionId, { success: true, events, complete, next_sequence: String(next) });
  }

  commitSessionEvent(session, type, payload, { broadcast = true } = {}) {
    const envelopeBase = { garp: GARP_SEMANTIC_VERSION, type, request_id: null, session_id: session.sessionId, timestamp: new Date().toISOString(), sequence: null, payload };
    let committed;
    try {
      committed = session.commitEvent(envelopeBase);
    } catch (error) {
      if (error?.code === GarpErrorCode.EVENT_QUEUE_OVERFLOW || error?.code === GarpErrorCode.EVENT_SEQUENCE_OVERFLOW) session.state = "FAILED";
      throw error;
    }
    if (broadcast) {
      for (const connection of this.connections) {
        if (connection.authenticated && session.ownerConnection === connection) connection.sendEnvelope(committed, false);
      }
    }
    return committed;
  }

  applyProviderChange(session, provider, _fencing = null) {
    const previous = session.provider;
    session.provider = provider;
    session.authoritativeProvider = provider;
    this.commitSessionEvent(session, "PROVIDER_CHANGED", { previous_provider: previous, provider, page_generation: String(session.pageGeneration) });
  }

  async recoverSession(session, reason) {
    if (session.state === "CLOSED") return;
    session.state = "RECOVERING";
    const deadline = monotonicNow() + Number(GARP_DEFAULT_RECOVERY_DEADLINE_MS);
    this.commitSessionEvent(session, "RECOVERY_STATE", { state: "RECOVERING", reason, deadline_remaining_ms: String(GARP_DEFAULT_RECOVERY_DEADLINE_MS) });
    while (monotonicNow() < deadline && session.state === "RECOVERING") {
      try {
        const result = await this.callChild(session, "InspectReady", { provider: session.provider, prompt_request_id: null });
        if (result.input_ready && result.authenticated !== false && !result.rate_limited) {
          session.inputState = "READY";
          session.state = session.activeRequestId ? "BUSY" : "READY";
          this.commitSessionEvent(session, "RECOVERY_STATE", { state: "RECOVERED", reason, deadline_remaining_ms: "0" });
          this.commitSessionEvent(session, "SESSION_READY", { provider: session.provider, tab_id: session.tabId, url: session.pageURL, page_generation: String(session.pageGeneration) });
          return;
        }
      } catch (_) {}
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    const activeRequestId = session.activeRequestId;
    if (activeRequestId) {
      const request = this.requestManager.requests.get(activeRequestId);
      if (request && !request.terminalCommitted) {
        await this.requestManager.failCandidate(request, GarpErrorCode.RECOVERY_FAILED, "Recovery deadline expired");
      }
    }
    session.state = "FAILED";
    this.commitSessionEvent(session, "RECOVERY_STATE", { state: "FAILED", reason, deadline_remaining_ms: "0" });
  }

  async callChild(session, operation, payload = {}) {
    const tab = this.sessionManager.getTabForSession(session);
    const browser = tab.linkedBrowser;
    const windowGlobal = browser?.browsingContext?.currentWindowGlobal;
    if (!windowGlobal) throw new GarpError(GarpErrorCode.TAB_UNAVAILABLE, "Browser content is not ready", { retryable: true });
    const actor = windowGlobal.getActor("AIAutomation");
    if (!actor) throw new GarpError(GarpErrorCode.STALE_ACTOR, "AIAutomation actor unavailable", { retryable: true });

    if (session.actorObject && session.actorObject !== actor) {
      session.incrementPageGeneration(browser.currentURI.spec);
      session.actorInstance = null;
      this.commitSessionEvent(session, "NAVIGATION", { page_generation: String(session.pageGeneration), url: browser.currentURI.spec });
    } else if (session.pageURL && session.pageURL !== browser.currentURI.spec) {
      session.incrementPageGeneration(browser.currentURI.spec);
      this.commitSessionEvent(session, "NAVIGATION_DRIFT", { page_generation: String(session.pageGeneration), reason: "UNEXPECTED_URL" });
      if (session.activeRequestId) throw new GarpError(GarpErrorCode.NAVIGATION_DRIFT, "URL changed during active prompt", { reason: "UNEXPECTED_URL" });
    }
    session.actorObject = actor;
    session.pageURL = browser.currentURI.spec;
    const capturedActor = actor;
    const capturedGeneration = session.pageGeneration;
    const expectedActorInstance = session.actorInstance;
    const result = await capturedActor.sendQuery(`GARP:${operation}`, {
      ...payload,
      session_id: session.sessionId,
      page_generation: String(capturedGeneration),
      actor_instance: expectedActorInstance,
      prompt_request_id: payload.prompt_request_id ?? null,
      provider: payload.provider ?? null,
    });
    if (session.actorObject !== capturedActor || session.pageGeneration !== capturedGeneration) throw new GarpError(GarpErrorCode.STALE_ACTOR, "Result returned by stale browser actor", { retryable: true });
    if (!result || typeof result !== "object") throw new GarpError(GarpErrorCode.PROVIDER_ERROR, "Child actor returned invalid result");
    if (result.fencing?.session_id && result.fencing.session_id !== session.sessionId) throw new GarpError(GarpErrorCode.STALE_ACTOR, "Result session fence mismatch");
    if (result.fencing?.page_generation !== undefined && BigInt(result.fencing.page_generation) !== session.pageGeneration) throw new GarpError(GarpErrorCode.STALE_ACTOR, "Result page generation fence mismatch");
    if (result.fencing?.actor_instance) {
      if (session.actorInstance && session.actorInstance !== result.fencing.actor_instance) throw new GarpError(GarpErrorCode.STALE_ACTOR, "Actor instance mismatch");
      session.actorInstance = result.fencing.actor_instance;
    }
    if (payload.provider && result.fencing?.provider && result.fencing.provider !== session.provider) throw new GarpError(GarpErrorCode.STALE_ACTOR, "Provider fence mismatch");
    return result;
  }
}

export { GARP_APPLICATION_LIMIT_DEFAULT };
