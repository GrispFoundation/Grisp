import { GarpRequest } from "./GarpRequest.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

function uuid() { return crypto.randomUUID(); }

export class GarpRequestManager {
  constructor(service, sessionManager, providerRegistry) {
    this.service = service;
    this.sessionManager = sessionManager;
    this.providerRegistry = providerRegistry;
    this.requests = new Map();
    this.subscribers = new Map();
  }

  get(requestId) {
    const request = this.requests.get(requestId);
    if (!request) throw new GarpError("REQUEST_NOT_FOUND", `Request not found: ${requestId}`);
    return request;
  }

  subscribe(requestId, connection) {
    let set = this.subscribers.get(requestId);
    if (!set) {
      set = new Set();
      this.subscribers.set(requestId, set);
    }
    set.add(connection);
  }

  unsubscribeConnection(connection) {
    for (const set of this.subscribers.values()) set.delete(connection);
  }

  emit(request, type, payload, extra = {}) {
    const options = {
      request_id: request.requestId,
      session_id: request.sessionId,
      message_id: request.messageId || undefined,
      sequence: request.nextSequence(),
      page_generation: request.pageGeneration || undefined,
      timestamp: new Date().toISOString(),
      ...extra,
    };
    const subscribers = this.subscribers.get(request.requestId) || [];
    for (const connection of subscribers) {
      connection.send(type, payload, options);
    }
    return options.sequence;
  }

  startPrompt(connection, sessionId, requestId, prompt, options = {}) {
    if (!requestId) requestId = uuid();
    if (this.requests.has(requestId)) {
      const existing = this.requests.get(requestId);
      if (existing.prompt !== prompt || existing.sessionId !== sessionId) {
        throw new GarpError(GarpErrorCode.REQUEST_ID_REUSE, "request_id already exists with different content");
      }
      this.subscribe(requestId, connection);
      return existing;
    }

    const session = this.sessionManager.get(sessionId);
    session.assertIdle();
    const request = new GarpRequest(requestId, sessionId, prompt, options);
    this.requests.set(requestId, request);
    this.subscribe(requestId, connection);
    session.activeRequestId = requestId;
    session.lastRequestId = requestId;
    session.state = "BUSY";
    request.pageGeneration = session.pageGeneration;

    this.runPrompt(request).catch(error => this.fail(request, error));
    return request;
  }

  async runPrompt(request) {
    const session = this.sessionManager.get(request.sessionId);
    const adapter = this.providerRegistry.get(session.provider);
    if (!adapter) throw new GarpError(GarpErrorCode.PROVIDER_NOT_FOUND, `Provider not found: ${session.provider}`);

    const snapshot = await this.service.callChild(session, "CaptureSnapshot", { provider: session.provider });
    if (snapshot?.error) throw this.errorFromChild(snapshot);
    request.lastMessageCount = Number(snapshot?.last_message_count || 0);
    request.lastText = String(snapshot?.last_message_text || "");
    session.lastMessageCount = request.lastMessageCount;
    session.lastMessageText = request.lastText;
    request.messageId = crypto.randomUUID();
    this.emit(request, "generation_started", {
      state: "STARTING",
      submission_snapshot: snapshot,
    });

    const inject = await this.service.callChild(session, "InjectPrompt", {
      provider: session.provider,
      prompt: request.prompt,
      forceFocus: !!request.options.force_focus,
      simulateEnter: !!request.options.simulate_enter,
    });
    if (inject?.error) throw this.errorFromChild(inject);
    request.state = "STREAMING";
    session.generationState = "STREAMING";
    this.emit(request, "input_submitted", {
      state: "SUBMITTED",
      input_method: inject.input_method || "dom_event",
      submit_method: inject.submit_method || "button_click",
    });
    this.observe(request).catch(error => this.fail(request, error));
  }

  errorFromChild(result) {
    return new GarpError(result.code || GarpErrorCode.GENERATION_FAILED, result.error || "Firefox child actor operation failed", {
      state: result.state || "ERROR",
      retryable: !!result.retryable,
      details: result,
    });
  }

  async observe(request) {
    const session = this.sessionManager.get(request.sessionId);
    const timeout = Number(request.options.timeout_ms || 180000);
    const intervalMs = 500;
    const settleTicks = 6;
    let lastObserved = request.lastText;
    let stableTicks = 0;
    let ticks = 0;

    for (;;) {
      if (!this.requests.has(request.requestId)) return;
      if (request.state === "CANCELLED" || request.state === "COMPLETE" || request.state === "FAILED") return;
      ticks++;
      if (Date.now() - request.startedAt > timeout) {
        throw new GarpError(GarpErrorCode.GENERATION_TIMEOUT, "Generation timeout", { retryable: true, state: "TIMEOUT" });
      }

      const currentTab = this.sessionManager.getTabForSession(session);
      session.markPageGeneration(session.pageGeneration, currentTab.linkedBrowser.currentURI.spec);
      request.pageGeneration = session.pageGeneration;

      const result = await this.service.callChild(session, "ObserveGeneration", {
        provider: session.provider,
        previous_message_count: request.lastMessageCount,
        previous_message_text: request.lastText,
      });
      if (result?.error) {
        throw this.errorFromChild(result);
      }

      if (Number(result.page_generation || session.pageGeneration) > session.pageGeneration) {
        session.markPageGeneration(Number(result.page_generation), currentTab.linkedBrowser.currentURI.spec);
        request.pageGeneration = session.pageGeneration;
      }

      const text = String(result.text || "");
      const done = !!result.done;
      const continued = !!result.continued;
      const count = Number(result.message_count || 0);

      if (result.authenticated === false || result.state === "AUTH_REQUIRED") {
        throw new GarpError(GarpErrorCode.AUTH_REQUIRED, "Provider authentication required", { state: "AUTH_REQUIRED", provider: session.provider });
      }
      if (result.rate_limited) {
        throw new GarpError(GarpErrorCode.PROVIDER_RATE_LIMIT, "Provider rate limit detected", { state: "RATE_LIMITED", retryable: true, provider: session.provider });
      }

      if (result.message_id && request.message_id_authoritative !== true) {
        request.messageId = result.message_id;
        request.message_id_authoritative = true;
      }

      if (continued) {
        request.continuationCount += 1;
        this.emit(request, "continuation_submitted", {
          count: request.continuationCount,
          reason: result.continuation_reason || "provider_length_limit",
        });
        stableTicks = 0;
      }

      const responseIdentified =
        !request.responseStarted &&
        ((count > request.lastMessageCount) ||
         (text && text !== request.lastText));

      if (responseIdentified) {
        request.responseStarted = true;
      }

      if (request.responseStarted && text && text !== lastObserved) {
        stableTicks = 0;
        lastObserved = text;
        request.text = text;
        this.emit(request, "generation_delta", {
          text_delta: this.delta(request.lastText, text),
          text_revision: ticks,
        });
        request.lastText = text;
      } else if (request.responseStarted && text) {
        stableTicks += 1;
      }

      if (result.continuation_required) {
        request.state = "CONTINUATION_REQUIRED";
        this.emit(request, "continuation_required", {
          reason: result.continuation_reason || "provider_length_limit",
        });
        if (request.options.auto_continue === false) {
          request.state = "COMPLETE";
          request.completedAt = Date.now();
          this.complete(request, session, result);
          return;
        }
        if (request.continuationCount >= Number(request.options.max_continuations || 8)) {
          throw new GarpError(GarpErrorCode.CONTINUATION_FAILED, "Maximum automatic continuations exceeded", { state: "CONTINUATION_REQUIRED" });
        }
        const continued = await this.service.callChild(session, "ContinueGeneration", {
          provider: session.provider,
          reason: result.continuation_reason || "provider_length_limit",
        });
        if (continued?.error) throw this.errorFromChild(continued);
        request.continuationCount += 1;
        request.state = "STREAMING";
        this.emit(request, "continuation_submitted", {
          count: request.continuationCount,
          reason: result.continuation_reason || "provider_length_limit",
        });
      } else if (request.responseStarted && done && text && stableTicks >= Math.max(2, settleTicks)) {
        this.complete(request, session, result);
        return;
      } else if (request.responseStarted && done && text && stableTicks >= 2) {
        this.complete(request, session, result);
        return;
      }

      await new Promise(resolve => setTimeout(resolve, intervalMs));
    }
  }

  delta(previous, current) {
    if (!previous) return current;
    if (current.startsWith(previous)) return current.slice(previous.length);
    return current;
  }

  complete(request, session, result) {
    request.state = "COMPLETE";
    request.completedAt = Date.now();
    session.state = "READY";
    session.generationState = "IDLE";
    session.activeRequestId = null;
    if (request.messageId) session.lastMessageId = request.messageId;
    session.lastMessageText = request.text;
    session.lastMessageCount = Number(result.message_count || session.lastMessageCount);
    this.emit(request, "generation_completed", {
      content: request.text,
      format: "text",
      finish_reason: result.finish_reason || "stop",
      provider_state: result.provider_state || "idle",
      response_identity: {
        message_id: request.messageId,
        message_count: session.lastMessageCount,
      },
    });
  }

  fail(request, error) {
    if (request.state === "COMPLETE" || request.state === "CANCELLED") return;
    request.state = "FAILED";
    request.completedAt = Date.now();
    request.error = {
      code: error?.code || GarpErrorCode.GENERATION_FAILED,
      message: error?.message || String(error),
    };
    const session = this.sessionManager.sessions.get(request.sessionId);
    if (session) {
      session.state = error?.state === "AUTH_REQUIRED" ? "AUTH_REQUIRED" : "ERROR";
      session.generationState = "FAILED";
      session.activeRequestId = null;
    }
    this.emit(request, "generation_failed", request.error);
  }

  cancel(requestId, reason = "cancelled") {
    const request = this.get(requestId);
    const session = this.sessionManager.get(request.sessionId);
    if (request.state === "COMPLETE" || request.state === "FAILED" || request.state === "CANCELLED") return request;
    request.state = "CANCELLED";
    request.completedAt = Date.now();
    this.service.callChild(session, "CancelGeneration", { provider: session.provider }).catch(() => {});
    session.state = "READY";
    session.generationState = "IDLE";
    session.activeRequestId = null;
    return request;
  }
}
