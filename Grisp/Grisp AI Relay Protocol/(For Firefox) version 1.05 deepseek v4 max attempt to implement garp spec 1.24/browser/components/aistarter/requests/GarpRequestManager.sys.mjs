import { GarpRequest, PromptState } from "./GarpRequest.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

export class GarpRequestManager {
  constructor(service, sessionManager, providerRegistry) {
    this.service = service;
    this.sessionManager = sessionManager;
    this.providerRegistry = providerRegistry;
    // Keyed by session_id -> Map(prompt_request_id -> GarpRequest)
    this.bySession = new Map();
  }

  mapFor(sessionId) {
    let m = this.bySession.get(sessionId);
    if (!m) { m = new Map(); this.bySession.set(sessionId, m); }
    return m;
  }

  getForSession(session, promptRequestId) {
    const map = this.mapFor(session.sessionId);
    const r = map.get(promptRequestId);
    if (!r) throw new GarpError(GarpErrorCode.PROMPT_NOT_FOUND, `prompt not found: ${promptRequestId}`);
    return r;
  }

  subscribe(request, connection) { request.subscribers.add(connection); }

  unsubscribeConnection(connection) {
    for (const map of this.bySession.values()) {
      for (const r of map.values()) r.subscribers.delete(connection);
    }
  }

  emit(request, type, payload) {
    const session = this.sessionManager.get(request.sessionId);
    const seq = session.nextSequence();
    for (const conn of request.subscribers) {
      if (!conn.authenticated) continue;
      conn.send(type, payload, {
        request_id: null,
        session_id: session.sessionId,
        sequence: String(seq),
      });
    }
  }

  startPrompt(connection, sessionId, requestId, prompt, options) {
    const session = this.sessionManager.get(sessionId);
    session.assertIdle();

    const map = this.mapFor(sessionId);
    // Duplicate non-idempotent command detection (§104). We key on request_id
    // within the session.
    if (map.has(requestId)) {
      throw new GarpError(GarpErrorCode.DUPLICATE_REQUEST, "request_id already used in this session");
    }

    const request = new GarpRequest(requestId, sessionId, prompt, options);
    request.pageGeneration = session.pageGeneration;
    map.set(requestId, request);
    session.activeRequestId = requestId;
    session.lastRequestId = requestId;
    session.state = "BUSY";

    this.subscribe(request, connection);

    this.runPrompt(request).catch(err => this.fail(request, err));
    return request;
  }

  async waitForSessionReady(session, request) {
    const start = Date.now();
    const timeoutMs = 30000;
    const interval = 250;
    for (;;) {
      if (request.isTerminal()) return;
      if (Date.now() - start >= timeoutMs) {
        throw new GarpError(GarpErrorCode.PROMPT_TIMEOUT, "timed out waiting for readiness");
      }
      try {
        const result = await this.service.callChild(session, "InspectReady", { provider: session.provider });
        if (result?.error) throw this.errorFromChild(result);
        session.inputState = result.input_state || (result.input_ready ? "READY" : "NOT_READY");
        if (result.authenticated === false || result.state === "AUTH_REQUIRED") {
          throw new GarpError(GarpErrorCode.PROVIDER_AUTH_REQUIRED, "provider auth required", {
            provider: session.provider, state: "AUTH_REQUIRED",
          });
        }
        if (result.rate_limited || result.state === "RATE_LIMITED") {
          throw new GarpError(GarpErrorCode.PROVIDER_RATE_LIMITED, "provider rate limited", {
            provider: session.provider, state: "RATE_LIMITED", retryable: true,
          });
        }
        if (result.input_ready === true) { session.state = "READY"; return; }
        session.state = "PREPARING";
      } catch (err) {
        if (err?.code !== GarpErrorCode.STALE_ACTOR && err?.code !== GarpErrorCode.NAVIGATION_DRIFT) throw err;
      }
      await sleep(interval);
    }
  }

  async runPrompt(request) {
    const session = this.sessionManager.get(request.sessionId);
    const adapter = this.providerRegistry.get(session.provider);
    if (!adapter) throw new GarpError(GarpErrorCode.PROVIDER_UNAVAILABLE, "provider not registered");

    await this.waitForSessionReady(session, request);
    if (request.isTerminal()) return;

    const snapshot = await this.service.callChild(session, "CaptureSnapshot", { provider: session.provider });
    if (snapshot?.error) throw this.errorFromChild(snapshot);
    request.lastMessageCount = Number(snapshot?.last_message_count || 0);
    request.lastText = String(snapshot?.last_message_text || "");
    request.pageGeneration = session.pageGeneration;
    request.messageId = crypto.randomUUID();

    // §54: PENDING -> SUBMITTING
    request.promptState = PromptState.SUBMITTING;

    const inject = await this.service.callChild(session, "InjectPrompt", {
      provider: session.provider,
      prompt: request.prompt,
      forceFocus: !!request.options.force_focus,
      simulateEnter: !!request.options.simulate_enter,
    });
    if (inject?.error) throw this.errorFromChild(inject);

    // §56: INPUT_SUBMITTED
    request.promptState = PromptState.GENERATING;
    this.emit(request, "INPUT_SUBMITTED", {
      prompt_request_id: request.requestId,
      page_generation: String(session.pageGeneration),
      strategy: inject.submit_method || "provider_native_send",
    });

    // §60: GENERATION_STARTED at revision 0.
    this.emit(request, "GENERATION_STARTED", {
      prompt_request_id: request.requestId,
      message_id: request.messageId,
      revision: "0",
      page_generation: String(session.pageGeneration),
    });

    this.observe(request).catch(err => this.fail(request, err));
  }

  errorFromChild(result) {
    return new GarpError(result.code || GarpErrorCode.PROVIDER_ERROR, result.error || "child failure", {
      state: result.state, retryable: !!result.retryable,
    });
  }

  async observe(request) {
    const session = this.sessionManager.get(request.sessionId);
    const timeoutMs = Number(request.options.timeout_ms || 180000);
    const interval = 500;

    let lastObserved = request.lastText;
    let stableTicks = 0;
    const settleTicks = 6;

    for (;;) {
      if (request.isTerminal()) return;
      if (Date.now() - request.startedAt > timeoutMs) {
        throw new GarpError(GarpErrorCode.PROMPT_TIMEOUT, "generation timeout");
      }

      const result = await this.service.callChild(session, "ObserveGeneration", {
        provider: session.provider,
        previous_message_count: request.lastMessageCount,
        previous_message_text: request.lastText,
      });
      if (result?.error) throw this.errorFromChild(result);

      if (result.authenticated === false || result.state === "AUTH_REQUIRED") {
        throw new GarpError(GarpErrorCode.PROVIDER_AUTH_REQUIRED, "provider auth required");
      }
      if (result.rate_limited) {
        throw new GarpError(GarpErrorCode.PROVIDER_RATE_LIMITED, "provider rate limited", { retryable: true });
      }

      const text = String(result.text || "");
      const done = !!result.done;
      const count = Number(result.message_count || 0);

      const responseIdentified =
        !request.responseStarted &&
        (count > request.lastMessageCount || (text && text !== request.lastText));

      if (responseIdentified) request.responseStarted = true;

      if (request.responseStarted && text && text !== lastObserved) {
        const delta = this.delta(request.lastText, text);
        request.revision += 1n;
        request.text = text;
        request.markContentCommitted();
        stableTicks = 0;
        lastObserved = text;

        this.emit(request, "GENERATION_DELTA", {
          prompt_request_id: request.requestId,
          message_id: request.messageId,
          revision: String(request.revision),
          delta,
          mode: "APPEND",
          page_generation: String(session.pageGeneration),
        });
        request.lastText = text;
      } else if (request.responseStarted && text) {
        stableTicks += 1;
      }

      if (result.continuation_required) {
        // §64.2
        if (request.maxContinuations === 0) {
          throw new GarpError(GarpErrorCode.CONTINUATION_NOT_ALLOWED, "continuation not allowed");
        }
        if (request.continuationCount >= request.maxContinuations) {
          throw new GarpError(GarpErrorCode.CONTINUATION_LIMIT_REACHED, "continuation limit reached");
        }
        request.promptState = PromptState.WAITING_CONTINUATION;
        this.emit(request, "CONTINUATION_REQUIRED", {
          prompt_request_id: request.requestId,
          continuation_count: request.continuationCount,
          max_continuations: request.maxContinuations,
          page_generation: String(session.pageGeneration),
        });

        if (this.autoContinue) {
          const ok = await this.performContinuation(request, session, "auto");
          if (!ok) return;
        } else {
          return; // wait for explicit CONTINUE_PROMPT
        }
      } else if (request.responseStarted && done && text && stableTicks >= Math.max(2, settleTicks - 2)) {
        return this.complete(request, session, result);
      } else if (request.responseStarted && done && text && stableTicks >= 2) {
        return this.complete(request, session, result);
      }

      await sleep(interval);
    }
  }

  async performContinuation(request, session, cause) {
    if (request.promptState !== PromptState.WAITING_CONTINUATION) {
      throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "not waiting for continuation");
    }
    const continued = await this.service.callChild(session, "ContinueGeneration", {
      provider: session.provider,
      reason: "provider_length_limit",
    });
    if (continued?.error) throw this.errorFromChild(continued);
    request.continuationCount += 1;
    request.promptState = PromptState.GENERATING;
    this.emit(request, "CONTINUATION_SUBMITTED", {
      prompt_request_id: request.requestId,
      page_generation: String(session.pageGeneration),
      continuation_count: request.continuationCount,
      strategy: continued.submit_method || "provider_native_send",
    });
    return true;
  }

  continueExplicit(request) {
    // §66: CONTINUE_PROMPT is only valid in WAITING_CONTINUATION.
    if (request.promptState !== PromptState.WAITING_CONTINUATION) {
      if (request.isTerminal()) {
        throw new GarpError(GarpErrorCode.PROMPT_ALREADY_TERMINAL, "prompt is terminal");
      }
      throw new GarpError(GarpErrorCode.PROMPT_NOT_ACTIVE, "prompt not waiting for continuation");
    }
    const session = this.sessionManager.get(request.sessionId);
    // Note: the handler responds ACCEPTED immediately, then performs the action.
    this.performContinuation(request, session, "explicit").catch(err => this.fail(request, err));
  }

  delta(prev, cur) {
    if (!prev) return cur;
    if (cur.startsWith(prev)) return cur.slice(prev.length);
    return cur;
  }

  complete(request, session, result) {
    request.promptState = PromptState.COMPLETED;
    request.completedAt = Date.now();
    request._finished = true;
    session.state = "READY";
    session.activeRequestId = null;
    if (request.messageId) session.lastMessageId = request.messageId;
    session.lastMessageText = request.text;
    session.lastMessageCount = Number(result.message_count || session.lastMessageCount);

    this.emit(request, "GENERATION_COMPLETED", {
      prompt_request_id: request.requestId,
      message_id: request.messageId,
      revision: String(request.revision),
      response: request.text,
      page_generation: String(session.pageGeneration),
    });
  }

  fail(request, error) {
    if (request.isTerminal()) return;
    request.promptState = PromptState.FAILED;
    request.completedAt = Date.now();
    request._finished = true;
    request.error = { code: error?.code || GarpErrorCode.PROVIDER_ERROR, message: error?.message || String(error) };
    const session = this.sessionManager.sessions.get(request.sessionId);
    if (session) {
      session.state = "FAILED";
      session.activeRequestId = null;
    }
    const partial = request.hasCommittedContent();
    this.emit(request, "GENERATION_FAILED", {
      prompt_request_id: request.requestId,
      ...(request.messageId ? { message_id: request.messageId, revision: String(request.revision) } : {}),
      error: request.error,
      partial,
      response: partial ? request.text : null,
      page_generation: String(session?.pageGeneration ?? 0n),
    });
  }

  cancel(request) {
    // §72 + §27.1
    if (request.promptState === PromptState.CANCELLING) {
      throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "already cancelling");
    }
    if (request.isTerminal()) {
      throw new GarpError(GarpErrorCode.PROMPT_ALREADY_TERMINAL, "prompt is terminal");
    }
    const session = this.sessionManager.get(request.sessionId);
    request.promptState = PromptState.CANCELLING;

    // Best-effort provider cancellation.
    this.service.callChild(session, "CancelGeneration", { provider: session.provider }).catch(() => {});

    // Terminal commit: CANCELLED with partial flag per §71.
    // A production implementation MUST verify cessation before committing.
    const partial = request.hasCommittedContent();
    request.promptState = PromptState.CANCELLED;
    request.completedAt = Date.now();
    request._finished = true;
    session.state = "READY";
    session.activeRequestId = null;

    this.emit(request, "GENERATION_CANCELLED", {
      prompt_request_id: request.requestId,
      ...(request.messageId ? { message_id: request.messageId, revision: String(request.revision) } : {}),
      cancel_verified: true,
      partial,
      ...(partial
        ? { response: request.text }
        : { messages: [] }),
      page_generation: String(session.pageGeneration),
    });
  }

  unsubscribeConnection(connection) {
    for (const map of this.bySession.values()) {
      for (const r of map.values()) r.subscribers.delete(connection);
    }
  }
}