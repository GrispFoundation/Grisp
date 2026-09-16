import { GarpRequest } from "./GarpRequest.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";
import {
  GARP_DEFAULT_CONTINUATION_WAIT_MS,
  GARP_DEFAULT_RECOVERY_DEADLINE_MS,
  GARP_MAX_GENERATION_BUFFER_MB,
  GARP_MAX_RESPONSE_SIZE,
} from "../garp/GarpRegistry.sys.mjs";
import { byteLength, monotonicNow, uuid } from "../garp/GarpUtil.sys.mjs";

const TERMINAL = new Set(["COMPLETED", "FAILED", "CANCELLED"]);
const ACTIVE = new Set(["PENDING", "SUBMITTING", "GENERATING", "WAITING_CONTINUATION", "CANCELLING"]);

function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

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
    if (!request) throw new GarpError(GarpErrorCode.PROMPT_NOT_FOUND, `Prompt not found: ${requestId}`);
    return request;
  }

  getForSession(sessionId, requestId) {
    const request = this.get(requestId);
    if (request.sessionId !== sessionId) throw new GarpError(GarpErrorCode.PROMPT_NOT_FOUND, `Prompt not found in session: ${requestId}`);
    return request;
  }

  subscribe(requestId, connection) {
    const request = this.get(requestId);
    let set = this.subscribers.get(requestId);
    if (!set) { set = new Set(); this.subscribers.set(requestId, set); }
    set.add(connection);
    return request;
  }

  unsubscribeConnection(connection) {
    for (const set of this.subscribers.values()) set.delete(connection);
  }

  emitEvent(request, type, payload) {
    const session = this.sessionManager.get(request.sessionId);
    return session.enqueue(`event:${type}`, () => this.commitEventNow(request, session, type, payload));
  }

  commitEventNow(request, session, type, payload) {
    if (request.terminalCommitted && !["GENERATION_COMPLETED", "GENERATION_FAILED", "GENERATION_CANCELLED"].includes(type)) return null;
    try {
      const envelope = this.service.commitSessionEvent(session, type, payload, { broadcast: false });
      const subscribers = this.subscribers.get(request.requestId) || new Set();
      for (const connection of subscribers) connection.sendEnvelope(envelope, false);
      return envelope;
    } catch (error) {
      if (error?.code === GarpErrorCode.EVENT_QUEUE_OVERFLOW) session.state = "FAILED";
      throw error;
    }
  }

  startPrompt(connection, sessionId, requestId, prompt, options = {}) {
    const session = this.sessionManager.get(sessionId);
    session.assertIdle();
    if (this.requests.has(requestId)) throw new GarpError(GarpErrorCode.DUPLICATE_REQUEST, "Prompt request ID already exists");
    const request = new GarpRequest(requestId || uuid(), sessionId, prompt, options);
    request.provider = session.provider;
    request.lastPageGeneration = session.pageGeneration;
    request.actorInstance = session.actorInstance;
    session.reservePrompt(request.requestId);
    request.state = "PENDING";
    this.requests.set(request.requestId, request);
    this.subscribe(request.requestId, connection);

    const timeout = BigInt(options.timeout_ms || "0");
    if (timeout > 0n) {
      const deadline = monotonicNow() + Number(timeout);
      request.promptDeadline = deadline;
      this.scheduleDeadline(request, deadline, GarpErrorCode.PROMPT_TIMEOUT, "Prompt timeout");
    }

    this.runPrompt(request).catch(error => this.failCandidate(request, error?.code || GarpErrorCode.PROVIDER_ERROR, error?.message || String(error), error));
    return request;
  }

  scheduleDeadline(request, deadline, code, message) {
    const delay = Math.max(0, deadline - monotonicNow());
    setTimeout(() => {
      if (!this.requests.has(request.requestId) || request.terminalCommitted) return;
      if (monotonicNow() + 1 < deadline) return this.scheduleDeadline(request, deadline, code, message);
      this.failCandidate(request, code, message, new GarpError(code, message, { state: "FAILED" }));
    }, Math.min(delay + 10, 0x7fffffff));
  }

  async waitForReady(session, request) {
    const timeout = Number(request.options.ready_timeout_ms ?? request.options.timeout_ms ?? 30000);
    const deadline = monotonicNow() + timeout;
    while (monotonicNow() < deadline) {
      if (request.cancelAccepted) throw new GarpError(GarpErrorCode.PROMPT_CANCELLED, "Prompt cancelled during preparation");
      if (request.terminalCommitted) return false;
      try {
        const result = await this.service.callChild(session, "InspectReady", { provider: session.provider, prompt_request_id: request.requestId });
        if (result.error) throw this.errorFromChild(result);
        if (result.authenticated === false || result.state === "AUTH_REQUIRED") throw new GarpError(GarpErrorCode.PROVIDER_AUTH_REQUIRED, "Provider authentication required");
        if (result.rate_limited || result.state === "RATE_LIMITED") throw new GarpError(GarpErrorCode.PROVIDER_RATE_LIMITED, "Provider rate limited");
        session.inputState = result.input_state || (result.input_ready ? "READY" : "NOT_READY");
        if (result.input_ready) { if (session.state === "PREPARING" || session.state === "RETRYING") session.transition("READY"); return true; }
      } catch (error) {
        if (![GarpErrorCode.STALE_ACTOR, GarpErrorCode.NAVIGATION_DRIFT, GarpErrorCode.TAB_UNAVAILABLE].includes(error?.code)) throw error;
      }
      await sleep(250);
    }
    throw new GarpError(GarpErrorCode.PROMPT_TIMEOUT, "Provider input did not become ready before timeout");
  }

  async runPrompt(request) {
    const session = this.sessionManager.get(request.sessionId);
    await this.waitForReady(session, request);
    if (request.terminalCommitted) return;
    request.state = "SUBMITTING";
    const snapshot = await this.service.callChild(session, "CaptureSnapshot", { provider: session.provider, prompt_request_id: request.requestId });
    if (snapshot.error) throw this.errorFromChild(snapshot);
    request.lastMessageCount = Number(snapshot.last_message_count || 0);
    request.baselineMessageCount = request.lastMessageCount;
    request.lastObservedText = String(snapshot.last_message_text || "");
    request.baselineMessageText = request.lastObservedText;
    request.lastPageGeneration = session.pageGeneration;
    request.actorInstance = session.actorInstance;

    const inject = await this.service.callChild(session, "InjectPrompt", {
      provider: session.provider,
      prompt: request.prompt,
      forceFocus: !!request.options.force_focus,
      simulateEnter: !!request.options.simulate_enter,
      prompt_request_id: request.requestId,
    });
    if (inject.error) throw this.errorFromChild(inject);
    if (!inject.provider_submission_verified) throw new GarpError(GarpErrorCode.SUBMISSION_FAILED, "Provider submission was not positively verified");
    request.state = "SUBMITTING";
    await this.emitEvent(request, "INPUT_SUBMITTED", { prompt_request_id: request.requestId, page_generation: String(session.pageGeneration), strategy: inject.strategy || "provider_native_send" });
    if (request.cancelAccepted) {
      this.startCancellationResolution(request, session);
      return;
    }
    this.observe(request).catch(error => this.failCandidate(request, error?.code || GarpErrorCode.PROVIDER_ERROR, error?.message || String(error), error));
  }

  async observe(request) {
    const session = this.sessionManager.get(request.sessionId);
    const timeout = Number(request.options.timeout_ms || 0);
    const deadline = timeout > 0 ? request.promptDeadline : null;
    let stableTicks = 0;
    let previousText = request.lastObservedText;

    for (;;) {
      if (!this.requests.has(request.requestId) || request.terminalCommitted) return;
      if (deadline !== null && monotonicNow() >= deadline) { this.failCandidate(request, GarpErrorCode.PROMPT_TIMEOUT, "Prompt timeout"); return; }
      if (request.state === "CANCELLING") { await this.resolveCancellationStep(request, session); return; }

      let result;
      try {
        result = await this.service.callChild(session, "ObserveGeneration", { provider: session.provider, previous_message_count: request.lastMessageCount, previous_message_text: request.lastObservedText, prompt_request_id: request.requestId });
      } catch (error) {
        if (error?.code === GarpErrorCode.NAVIGATION_DRIFT || error?.code === GarpErrorCode.STALE_ACTOR) { await this.handleNavigationDrift(request, session, error); return; }
        throw error;
      }
      if (result.provider_context_valid === false) {
        await this.service.commitSessionEvent(session, "NAVIGATION_DRIFT", { page_generation: String(session.pageGeneration), reason: "PROVIDER_CONTEXT_LOST" });
        this.failCandidate(request, GarpErrorCode.PROVIDER_UNAVAILABLE, "Authoritative provider context was lost", null, request.partial);
        this.service.recoverSession(session, "PROVIDER_CONTEXT_LOST").catch(() => {});
        return;
      }
      if (result.error) {
        const code = result.code || GarpErrorCode.PROVIDER_ERROR;
        if (code === GarpErrorCode.PROVIDER_AUTH_REQUIRED) {
          await this.service.commitSessionEvent(session, "PROVIDER_AUTH_REQUIRED", { provider: session.provider, reason: "LOGIN_REQUIRED", page_generation: String(session.pageGeneration) });
        } else if (code === GarpErrorCode.PROVIDER_RATE_LIMITED) {
          await this.service.commitSessionEvent(session, "PROVIDER_RATE_LIMITED", { provider: session.provider, retry_after_ms: "0", page_generation: String(session.pageGeneration) });
        } else {
          await this.service.commitSessionEvent(session, "PROVIDER_ERROR", { provider: session.provider, code, message: result.error || "Provider error", retryable: !!result.retryable, prompt_request_id: request.requestId, page_generation: String(session.pageGeneration) });
        }
        this.failCandidate(request, code, result.error);
        return;
      }
      request.lastPageGeneration = session.pageGeneration;
      request.actorInstance = session.actorInstance;
      const observedCount = Number(result.message_count || request.lastMessageCount);
      const previousCount = request.lastMessageCount;
      request.lastMessageCount = observedCount;
      const text = String(result.text ?? "");
      const textChanged = text !== request.lastObservedText;
      const responseIdentified = !request.responseStarted && (observedCount > previousCount || textChanged || result.authoritative_generation_started === true);

      if (!request.responseStarted && (responseIdentified || result.message_changed === true)) {
        const started = await session.enqueue("generation-started", () => {
          if (request.terminalCommitted || session.activeRequestId !== request.requestId) return false;
          request.responseStarted = true;
          request.state = "GENERATING";
          this.commitEventNow(request, session, "GENERATION_STARTED", { prompt_request_id: request.requestId, message_id: request.messageId, revision: "0", page_generation: String(session.pageGeneration) });
          return true;
        });
        if (!started) return;
      }

      if (request.responseStarted && textChanged) {
        const previous = request.content;
        let mode = "REPLACE";
        let delta = text;
        if (text.startsWith(previous)) { mode = "APPEND"; delta = text.slice(previous.length); }
        const bytes = byteLength(text);
        const transientBytes = byteLength(text);
        if (bytes > GARP_MAX_RESPONSE_SIZE) { this.failCandidate(request, GarpErrorCode.RESPONSE_TOO_LARGE, "Response exceeds max_response_size", null, request.partial); return; }
        if (transientBytes > GARP_MAX_GENERATION_BUFFER_MB * 1024 * 1024) { this.failCandidate(request, GarpErrorCode.GENERATION_BUFFER_LIMIT, "Generation buffer limit exceeded", null, request.partial); return; }
        const committed = await session.enqueue("generation-delta", () => {
          if (request.terminalCommitted || session.activeRequestId !== request.requestId) return false;
          const revision = request.revision + 1n;
          if (revision > 18446744073709551615n) throw new GarpError(GarpErrorCode.REVISION_GAP, "Message revision overflow");
          const envelope = this.commitEventNow(request, session, "GENERATION_DELTA", { prompt_request_id: request.requestId, message_id: request.messageId, revision: String(revision), delta, mode, page_generation: String(session.pageGeneration) });
          request.revision = revision;
          request.content = text;
          request.lastObservedText = text;
          request.partial = request.partial || text.length > 0;
          return !!envelope;
        });
        if (committed) stableTicks = 0;
      } else if (request.responseStarted && text) stableTicks++;

      await this.emitEvent(request, "GENERATION_PROGRESS", { prompt_request_id: request.requestId, message_count: request.lastMessageCount, page_generation: String(session.pageGeneration) });

      if (result.continuation_required) {
        await this.handleContinuationRequired(request, session, result);
        return;
      }

      if (request.responseStarted && result.done && stableTicks >= 2) {
        await this.completeCandidate(request, session, result);
        return;
      }
      previousText = text;
      await sleep(500);
    }
  }

  async handleContinuationRequired(request, session, result) {
    if (!request.responseStarted && !request.content) request.partial = false;
    if (request.options.max_continuations === undefined) request.maxContinuations = 8;
    if (request.cancelAccepted) { this.startCancellationResolution(request, session); return; }
    if (!result.continuation_supported && !result.continuation_available) { this.failCandidate(request, GarpErrorCode.CONTINUATION_NOT_AVAILABLE, "Provider continuation is unavailable"); return; }
    if (request.maxContinuations === 0) { this.failCandidate(request, GarpErrorCode.CONTINUATION_NOT_ALLOWED, "Continuation is disabled", null, request.partial); return; }
    if (request.continuationCount >= request.maxContinuations) { this.failCandidate(request, GarpErrorCode.CONTINUATION_LIMIT_REACHED, "Continuation limit reached", null, request.partial); return; }
    request.state = "WAITING_CONTINUATION";
    request.continuationWaitDeadline = monotonicNow() + Number(BigInt(this.service.capabilities.limits.continuation_wait_ms));
    await this.emitEvent(request, "CONTINUATION_REQUIRED", { prompt_request_id: request.requestId, continuation_count: request.continuationCount, max_continuations: request.maxContinuations, page_generation: String(session.pageGeneration) });
    this.scheduleDeadline(request, request.continuationWaitDeadline, GarpErrorCode.CONTINUATION_TIMEOUT, "Continuation timeout");
    if (request.options.auto_continue === true) this.autoContinue(request, session);
  }

  async autoContinue(request, session) {
    if (!this.requests.has(request.requestId) || request.terminalCommitted) return;
    try {
      const reserved = await this.reserveContinuation(request, session, "auto");
      if (!reserved) return;
      this.runContinuation(request, session, reserved.epoch).catch(error => this.failCandidate(request, error?.code || GarpErrorCode.PROVIDER_ERROR, error?.message || String(error), error));
    } catch (_) {}
  }

  async continuePrompt(connection, sessionId, promptRequestId) {
    const session = this.sessionManager.get(sessionId);
    const request = this.getForSession(sessionId, promptRequestId);
    if (request.terminal) throw new GarpError(GarpErrorCode.PROMPT_ALREADY_TERMINAL, "Prompt is terminal");
    if (request.state !== "WAITING_CONTINUATION") throw new GarpError(GarpErrorCode.PROMPT_NOT_ACTIVE, "Prompt is not waiting for continuation");
    if (session.ownerConnection && session.ownerConnection !== connection) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
    const reserved = await this.reserveContinuation(request, session, "explicit");
    if (!reserved) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Continuation reservation lost");
    this.runContinuation(request, session, reserved.epoch).catch(error => this.failCandidate(request, error?.code || GarpErrorCode.PROVIDER_ERROR, error?.message || String(error), error));
    return true;
  }

  async reserveContinuation(request, session, source) {
    return session.enqueue(`continue-reserve:${source}`, () => {
      if (request.terminalCommitted) return false;
      if (request.state !== "WAITING_CONTINUATION") {
        if (source === "auto") return false;
        throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Continuation reservation lost");
      }
      if (request.continuationCount >= request.maxContinuations) throw new GarpError(GarpErrorCode.CONTINUATION_LIMIT_REACHED, "Continuation limit reached");
      const epoch = ++request.continuationEpoch;
      request.state = "SUBMITTING";
      return { epoch };
    });
  }

  async runContinuation(request, session, epoch) {
    try {
      const result = await this.service.callChild(session, "ContinueGeneration", {
        provider: session.provider,
        prompt_request_id: request.requestId,
        continuation_epoch: epoch,
        reason: "provider_length_limit",
      });
      if (request.cancelAccepted || epoch !== request.continuationEpoch || request.terminalCommitted) return;
      if (result.error) throw this.errorFromChild(result);
      if (!result.provider_submission_verified) throw new GarpError(GarpErrorCode.SUBMISSION_FAILED, "Continuation submission was not positively verified");
      request.continuationCount += 1;
      request.state = "GENERATING";
      await this.emitEvent(request, "CONTINUATION_SUBMITTED", {
        prompt_request_id: request.requestId,
        page_generation: String(session.pageGeneration),
        continuation_count: request.continuationCount,
        strategy: result.strategy || "provider_native_send",
      });
      this.observe(request).catch(error => this.failCandidate(request, error?.code || GarpErrorCode.PROVIDER_ERROR, error?.message || String(error), error));
    } catch (error) {
      if (request.cancelAccepted || request.terminalCommitted) return;
      this.failCandidate(request, error?.code || GarpErrorCode.PROVIDER_ERROR, error?.message || String(error), error);
    }
  }

  async cancel(connection, sessionId, promptRequestId) {
    const session = this.sessionManager.get(sessionId);
    const request = this.getForSession(sessionId, promptRequestId);
    if (session.ownerConnection && session.ownerConnection !== connection) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
    if (request.terminal) throw new GarpError(GarpErrorCode.PROMPT_ALREADY_TERMINAL, "Prompt is terminal");
    if (request.state === "CANCELLING") throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Cancellation already in progress");
    if (!ACTIVE.has(request.state)) throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, `Cannot cancel from ${request.state}`);
    request.cancelAccepted = true;
    request.state = "CANCELLING";
    request.continuationEpoch += 1;
    await session.enqueue("cancel-accept", () => {
      if (session.state === "BUSY") session.transition("RECOVERING");
    });
    this.startCancellationResolution(request, session);
    return request;
  }

  startCancellationResolution(request, session) { this.resolveCancellationStep(request, session).catch(error => this.failCandidate(request, GarpErrorCode.RECOVERY_FAILED, error.message, error)); }

  async resolveCancellationStep(request, session) {
    if (request.terminalCommitted) return;
    const deadline = monotonicNow() + Number(BigInt(this.service.capabilities.limits.recovery_deadline_ms));
    let cancelIssued = false;
    while (monotonicNow() < deadline && !request.terminalCommitted) {
      try {
        if (!cancelIssued) {
          cancelIssued = true;
          await this.service.callChild(session, "CancelGeneration", { provider: session.provider, prompt_request_id: request.requestId });
        }
        const state = await this.service.callChild(session, "InspectProviderState", { provider: session.provider, prompt_request_id: request.requestId, previous_message_count: request.baselineMessageCount, previous_message_text: request.baselineMessageText });
        if (state?.error) throw this.errorFromChild(state);
        if (state.streaming === false && state.authoritative_cessation === true) {
          request.cancellationVerified = true;
          await this.cancelCandidate(request, session);
          return;
        }
        if (state.streaming === false && state.authoritative_completion === true && request.responseStarted) {
          await this.completeCandidate(request, session, state);
          return;
        }
      } catch (error) {
        if (error?.code === GarpErrorCode.STALE_ACTOR || error?.code === GarpErrorCode.NAVIGATION_DRIFT) {
          await sleep(250); continue;
        }
      }
      await sleep(250);
    }
    if (!request.terminalCommitted) this.failCandidate(request, GarpErrorCode.RECOVERY_FAILED, "Cancellation state could not be authoritatively established", null, request.partial);
  }

  async completeCandidate(request, session, result) {
    const candidate = { kind: "COMPLETED", request, session, fencing: this.currentFencing(request, session) };
    await session.enqueue("terminal-completed", () => this.commitTerminalCandidate(candidate, { content: request.content, revision: request.revision, result }));
  }

  async cancelCandidate(request, session) {
    const candidate = { kind: "CANCELLED", request, session, fencing: this.currentFencing(request, session) };
    await session.enqueue("terminal-cancelled", () => this.commitTerminalCandidate(candidate, null));
  }

  failCandidate(request, code, message, error = null, partialOverride = null) {
    const session = this.sessionManager.sessions.get(request.sessionId);
    if (!session || request.terminalCommitted) return Promise.resolve(false);
    const candidate = { kind: "FAILED", request, session, fencing: this.currentFencing(request, session), code, message, partial: partialOverride === null ? request.partial : !!partialOverride };
    return session.enqueue(`terminal-failed:${code}`, () => this.commitTerminalCandidate(candidate, { error: { code, message } }));
  }

  currentFencing(request, session) { return { session_id: session.sessionId, provider: session.provider, prompt_request_id: request.requestId, page_generation: session.pageGeneration, actor_instance: session.actorInstance, message_id: request.messageId }; }

  async commitTerminalCandidate(candidate, data) {
    const { request, session } = candidate;
    if (request.terminalCommitted) return false;
    if (request.sessionId !== session.sessionId || session.activeRequestId !== request.requestId) return false;
    if (candidate.fencing.provider !== session.provider || candidate.fencing.prompt_request_id !== request.requestId || candidate.fencing.message_id !== request.messageId) return false;
    if ((candidate.kind === "COMPLETED" || candidate.kind === "CANCELLED") && (candidate.fencing.page_generation !== session.pageGeneration || candidate.fencing.actor_instance !== session.actorInstance || !candidate.fencing.actor_instance)) return false;
    request.terminalCommitted = true;
    request.completedAt = monotonicNow();
    request.partial = request.partial || !!candidate.partial || request.content.length > 0;

    if (candidate.kind === "COMPLETED") {
      request.state = "COMPLETED";
      session.lastMessageId = request.messageId;
      session.lastMessageText = request.content;
      session.lastMessageCount = Math.max(session.lastMessageCount, request.lastMessageCount);
      session.clearActivePrompt();
      this.commitEventNow(request, session, "GENERATION_COMPLETED", { prompt_request_id: request.requestId, message_id: request.messageId, revision: String(request.revision), response: request.content, page_generation: String(session.pageGeneration) });
    } else if (candidate.kind === "CANCELLED") {
      request.state = "CANCELLED";
      session.clearActivePrompt();
      this.commitEventNow(request, session, "GENERATION_CANCELLED", { prompt_request_id: request.requestId, message_id: request.messageId, revision: String(request.revision), cancel_verified: true, partial: request.partial, response: request.content, page_generation: String(session.pageGeneration) });
    } else {
      request.state = "FAILED";
      request.error = { code: candidate.code, message: candidate.message };
      session.activeRequestId = null;
      session.generationState = "IDLE";
      if (candidate.code === GarpErrorCode.PROVIDER_AUTH_REQUIRED) session.state = "AUTH_REQUIRED";
      else if (candidate.code === GarpErrorCode.PROVIDER_RATE_LIMITED) session.state = "RATE_LIMITED";
      else if ([GarpErrorCode.RECOVERY_FAILED, GarpErrorCode.NAVIGATION_DRIFT, GarpErrorCode.PROVIDER_UNAVAILABLE, GarpErrorCode.RESPONSE_TOO_LARGE, GarpErrorCode.GENERATION_BUFFER_LIMIT].includes(candidate.code)) session.state = "RECOVERING";
      else if (candidate.code === GarpErrorCode.EVENT_QUEUE_OVERFLOW) session.state = "FAILED";
      else if (session.state !== "CLOSED") session.state = "READY";
      this.commitEventNow(request, session, "GENERATION_FAILED", { prompt_request_id: request.requestId, error: { code: candidate.code, message: candidate.message }, partial: request.partial, response: request.content.length ? request.content : null, page_generation: String(session.pageGeneration) });
    }
    return true;
  }

  async handleNavigationDrift(request, session, error) {
    if (request.terminalCommitted) return;
    if (session.state !== "RECOVERING" && session.state !== "CLOSED") session.state = "RECOVERING";
    await this.emitEvent(request, "NAVIGATION_DRIFT", { page_generation: String(session.pageGeneration), reason: error?.reason || "DOCUMENT_REPLACED" });
    await this.failCandidate(request, GarpErrorCode.NAVIGATION_DRIFT, "Navigation drift invalidated active prompt", error, request.partial);
    this.service.recoverSession(session, "DOCUMENT_REPLACED").catch(() => {});
  }

  async abortForSessionReset(session, reason = "SESSION_RESET") {
    const requestId = session.activeRequestId;
    if (!requestId) return;
    const request = this.requests.get(requestId);
    if (!request || request.terminalCommitted) return;
    try {
      await session.enqueue("reset-prompt", () => this.commitTerminalCandidate({
        kind: "FAILED",
        request,
        session,
        fencing: this.currentFencing(request, session),
        code: GarpErrorCode.RECOVERY_FAILED,
        message: reason === "SESSION_CLOSE" ? "Session closed while prompt was active" : "Prompt invalidated by RESET_SESSION",
        partial: request.partial,
      }, null));
    } catch (_) {}
    this.service.callChild(session, "CancelGeneration", { provider: session.provider, prompt_request_id: requestId }).catch(() => {});
  }

  errorFromChild(result) { return new GarpError(result.code || GarpErrorCode.PROVIDER_ERROR, result.error || "Provider operation failed"); }

  getResponse(request) {
    if (!TERMINAL.has(request.state)) throw new GarpError(GarpErrorCode.RESPONSE_NOT_READY, "The response is not terminally available");
    return { success: true, state: request.state, partial: request.partial, response: request.content.length ? request.content : null, ...(request.state === "FAILED" ? { error: request.error } : {}) };
  }

  prune(retentionMs) {
    const now = monotonicNow();
    for (const [id, request] of this.requests) {
      if (request.terminalCommitted && request.completedAt !== null && now - request.completedAt > retentionMs) { this.requests.delete(id); this.subscribers.delete(id); }
    }
  }
}
