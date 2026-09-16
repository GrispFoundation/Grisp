import { GarpRequest, PromptState } from "./GarpRequest.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";
import { GARP_DEFAULT_CONTINUATION_WAIT_MS, GARP_MAX_GENERATION_BUFFER_MB, GARP_MAX_RESPONSE_SIZE, } from "../garp/GarpRegistry.sys.mjs";
import { byteLength, createOneShotTimer, delayMs, monotonicNow, uuid, } from "../garp/GarpUtil.sys.mjs";
import { garpDebug, garpError } from "../GarpDebug.sys.mjs";
const ACTIVE = new Set(Object.values(PromptState).filter(x => !["COMPLETED", "FAILED", "CANCELLED"].includes(x)));
const sleep = ms => delayMs(ms);
export class GarpRequestManager {
    constructor(service, sessionManager) {
        this.service = service;
        this.sessionManager = sessionManager;
        this.requests = new Map();
        this.subscribers = new Map();
    }
    get(id) {
        const r = this.requests.get(id);
        if (!r)
            throw new GarpError(GarpErrorCode.PROMPT_NOT_FOUND, `Prompt not found: ${id}`);
        return r;
    }
    getForSession(sid, id) {
        const r = this.get(id);
        if (r.sessionId !== sid)
            throw new GarpError(GarpErrorCode.PROMPT_NOT_FOUND, `Prompt not found in session: ${id}`);
        return r;
    }
    subscribe(id, connection) {
        let s = this.subscribers.get(id);
        if (!s) {
            s = new Set();
            this.subscribers.set(id, s);
        }
        s.add(connection);
        garpDebug(2, "request subscribed", { request_id: id, subscribers: s.size });
        return this.get(id);
    }
    startPrompt(connection, sid, rid, prompt, options = {}) {
        garpDebug(1, "request manager startPrompt", {
            request_id: rid,
            session_id: sid,
            prompt_length: String(prompt ?? "").length,
            options,
        });
        const s = this.sessionManager.get(sid);
        s.assertIdle();
        if (this.requests.has(rid))
            throw new GarpError(GarpErrorCode.DUPLICATE_REQUEST, "Prompt request ID already exists");
        const r = new GarpRequest(rid || uuid(), sid, prompt, options);
        r.provider = s.provider;
        r.lastPageGeneration = s.pageGeneration;
        r.actorInstance = s.actorInstance;
        s.reservePrompt(r.requestId);
        this.requests.set(r.requestId, r);
        this.subscribe(r.requestId, connection);
        const timeout = BigInt(options.timeout_ms ?? "0");
        if (timeout > 0n) {
            r.promptDeadline = monotonicNow() + Number(timeout);
            this.scheduleTimer(r, r.promptDeadline, ++r.timeoutEpoch, GarpErrorCode.PROMPT_TIMEOUT, "Prompt timeout");
        }
        this.runPrompt(r).catch(e => {
            garpError("runPrompt rejected", {
                request_id: r.requestId,
                session_id: r.sessionId,
                provider: r.provider,
                state: r.state,
                code: e?.code || null,
                message: e?.message || String(e),
                stack: e?.stack || null,
            });
            this.failCandidate(r, e?.code || GarpErrorCode.PROVIDER_ERROR, e?.message || String(e), e);
        });
        return r;
    }
    scheduleTimer(r, deadline, epoch, code, message) {
        const delay = Math.max(0, deadline - monotonicNow());
        if (r.timeoutTimer) {
            try {
                r.timeoutTimer.cancel();
            }
            catch (_) { }
            r.timeoutTimer = null;
        }
        r.timeoutTimer = createOneShotTimer(() => {
            r.timeoutTimer = null;
            if (!this.requests.has(r.requestId) ||
                r.terminalCommitted ||
                epoch !== r.timeoutEpoch) {
                return;
            }
            if (monotonicNow() + 1 < deadline) {
                this.scheduleTimer(r, deadline, epoch, code, message);
                return;
            }
            this.failCandidate(r, code, message);
        }, Math.min(delay + 10, 0x7fffffff));
    }
    _emitNow(r, s, type, payload) {
        if (r.terminalCommitted && !type.startsWith("GENERATION_"))
            return null;

        const e = this.service.commitSessionEvent(
            s,
            type,
            payload,
            { broadcast: false }
        );

        const subscribers = this.subscribers.get(r.requestId) || new Set();

        garpDebug(1, "request event committed", {
            request_id: r.requestId,
            session_id: s.sessionId,
            provider: r.provider,
            type,
            sequence: e.sequence,
            subscribers: subscribers.size,
        });

        for (const c of subscribers) {
            if (!c.authenticated)
                continue;

            const sent = c.sendEnvelope(e, false);
            garpDebug(2, "request event sent", {
                request_id: r.requestId,
                session_id: s.sessionId,
                type,
                sequence: e.sequence,
                sent,
                connection_closed: !!c.closed,
            });
        }

        return e;
    }

    async emit(r, type, payload) {
        const s = this.sessionManager.get(r.sessionId);
        garpDebug(1, "request event queued", {
            request_id: r.requestId,
            session_id: s.sessionId,
            provider: r.provider,
            type,
            state: r.state,
            payload,
        });
        return s.enqueue(`event:${type}`, () =>
            this._emitNow(r, s, type, payload)
        );
    }
    async waitForReady(s, r) {
        const deadline = monotonicNow() + Number(r.options.ready_timeout_ms ?? r.options.timeout_ms ?? 30000);
        let attempt = 0;
        garpDebug(1, "prompt readiness wait begin", {
            request_id: r.requestId,
            session_id: s.sessionId,
            provider: s.provider,
            state: s.state,
        });
        while (monotonicNow() < deadline) {
            attempt++;
            if (r.terminalCommitted)
                return false;
            if (r.cancelAccepted)
                throw new GarpError(GarpErrorCode.PROMPT_CANCELLED, "Prompt cancelled during preparation");
            try {
                const x = await this.service.callChild(s, "InspectReady", { provider: s.provider, prompt_request_id: r.requestId });
                garpDebug(2, "InspectReady result", {
                    request_id: r.requestId,
                    session_id: s.sessionId,
                    attempt,
                    result: x,
                });
                if (x.error)
                    throw this.errorFromChild(x);
                if (x.authenticated === false || x.state === "AUTH_REQUIRED")
                    throw new GarpError(GarpErrorCode.PROVIDER_AUTH_REQUIRED, "Provider authentication required");
                if (x.rate_limited || x.state === "RATE_LIMITED")
                    throw new GarpError(GarpErrorCode.PROVIDER_RATE_LIMITED, "Provider rate limited");
                s.inputState = x.input_state || (x.input_ready ? "READY" : "NOT_READY");
                if (x.input_ready) {
                    if (s.state === "PREPARING" || s.state === "RETRYING")
                        s.transition("READY");
                    garpDebug(1, "prompt readiness confirmed", {
                        request_id: r.requestId,
                        session_id: s.sessionId,
                        attempt,
                        input_state: s.inputState,
                        page_generation: String(s.pageGeneration),
                    });
                    return true;
                }
            }
            catch (e) {
                garpDebug(2, "InspectReady exception", {
                    request_id: r.requestId,
                    session_id: s.sessionId,
                    attempt,
                    code: e?.code || null,
                    message: e?.message || String(e),
                });
                if (![GarpErrorCode.STALE_ACTOR, GarpErrorCode.NAVIGATION_DRIFT, GarpErrorCode.TAB_UNAVAILABLE].includes(e?.code))
                    throw e;
            }
            await sleep(250);
        }
        throw new GarpError(GarpErrorCode.PROMPT_TIMEOUT, "Provider input did not become ready before timeout");
    }
    async runPrompt(r) {
        const s = this.sessionManager.get(r.sessionId);
        garpDebug(1, "runPrompt begin", {
            request_id: r.requestId,
            session_id: r.sessionId,
            provider: s.provider,
            session_state: s.state,
            page_generation: String(s.pageGeneration),
            prompt_length: r.prompt.length,
        });
        garpDebug(2, "runPrompt waiting for ready", {
            request_id: r.requestId,
            session_id: s.sessionId,
            state: s.state,
        });
        await this.waitForReady(s, r);
        garpDebug(1, "runPrompt ready", {
            request_id: r.requestId,
            session_id: s.sessionId,
            state: s.state,
            input_state: s.inputState,
            page_generation: String(s.pageGeneration),
        });
        if (r.terminalCommitted)
            return;
        r.state = PromptState.SUBMITTING;
        garpDebug(2, "CaptureSnapshot begin", {
            request_id: r.requestId,
            session_id: s.sessionId,
        });
        const snap = await this.service.callChild(s, "CaptureSnapshot", { provider: s.provider, prompt_request_id: r.requestId });
        garpDebug(1, "CaptureSnapshot result", {
            request_id: r.requestId,
            session_id: s.sessionId,
            snapshot: snap,
        });
        if (snap.error)
            throw this.errorFromChild(snap);
        r.baselineMessageCount = Number(snap.last_message_count || 0);
        r.baselineMessageText = String(snap.last_message_text || "");
        r.lastMessageCount = r.baselineMessageCount;
        r.lastMessageText = r.baselineMessageText;
        r.lastPageGeneration = s.pageGeneration;
        r.actorInstance = s.actorInstance;
        garpDebug(1, "InjectPrompt begin", {
            request_id: r.requestId,
            session_id: s.sessionId,
            provider: s.provider,
            prompt_length: r.prompt.length,
            force_focus: !!r.options.force_focus,
            simulate_enter: !!r.options.simulate_enter,
        });
        const inj = await this.service.callChild(s, "InjectPrompt", { provider: s.provider, prompt: r.prompt, forceFocus: !!r.options.force_focus, simulateEnter: !!r.options.simulate_enter, prompt_request_id: r.requestId });
        garpDebug(1, "InjectPrompt result", {
            request_id: r.requestId,
            session_id: s.sessionId,
            result: inj,
        });
        if (inj.error)
            throw this.errorFromChild(inj);
        if (!inj.provider_submission_verified)
            throw new GarpError(GarpErrorCode.SUBMISSION_FAILED, "Provider submission was not positively verified");
        await this.emit(r, "INPUT_SUBMITTED", { prompt_request_id: r.requestId, page_generation: String(s.pageGeneration), strategy: inj.strategy || "provider_native_send" });
        if (r.cancelAccepted) {
            this.startCancellationResolution(r, s);
            return;
        }
        garpDebug(1, "starting generation observation", {
            request_id: r.requestId,
            session_id: s.sessionId,
            page_generation: String(s.pageGeneration),
        });
        this.observe(r).catch(e => {
            garpError("observe rejected", {
                request_id: r.requestId,
                session_id: r.sessionId,
                code: e?.code || null,
                message: e?.message || String(e),
                stack: e?.stack || null,
            });
            this.failCandidate(r, e?.code || GarpErrorCode.PROVIDER_ERROR, e?.message || String(e), e);
        });
    }
    async observe(r) {
        const s = this.sessionManager.get(r.sessionId);
        let stable = 0;
        let stableMessageCount = null;
        let stableText = null;
        let iteration = 0;
        garpDebug(1, "generation observation begin", {
            request_id: r.requestId,
            session_id: s.sessionId,
            provider: s.provider,
            page_generation: String(s.pageGeneration),
        });
        for (;;) {
            iteration++;
            if (r.terminalCommitted)
                return;
            if (r.state === PromptState.CANCELLING) {
                await this.resolveCancellationStep(r, s);
                return;
            }
            if (r.promptDeadline !== null && monotonicNow() >= r.promptDeadline) {
                await this.failCandidate(r, GarpErrorCode.PROMPT_TIMEOUT, "Prompt timeout");
                return;
            }
            let x;
            try {
                garpDebug(2, "ObserveGeneration call", {
                    request_id: r.requestId,
                    session_id: s.sessionId,
                    iteration,
                    previous_message_count: r.lastMessageCount,
                    previous_text_length: r.lastMessageText.length,
                });
                x = await this.service.callChild(s, "ObserveGeneration", { provider: s.provider, previous_message_count: r.lastMessageCount, previous_message_text: r.lastMessageText, prompt_request_id: r.requestId });
                garpDebug(2, "ObserveGeneration result", {
                    request_id: r.requestId,
                    session_id: s.sessionId,
                    iteration,
                    result: x,
                });
            }
            catch (e) {
                if ([GarpErrorCode.STALE_ACTOR, GarpErrorCode.NAVIGATION_DRIFT].includes(e?.code)) {
                    await this.handleNavigationDrift(r, s, e);
                    return;
                }
                throw e;
            }
            if (x.error) {
                garpDebug(1, "ObserveGeneration provider error", {
                    request_id: r.requestId,
                    session_id: s.sessionId,
                    iteration,
                    code: x.code || null,
                    error: x.error,
                });
                const code = x.code || GarpErrorCode.PROVIDER_ERROR;
                if (code === GarpErrorCode.PROVIDER_AUTH_REQUIRED)
                    await this.service.commitSessionEvent(s, "PROVIDER_AUTH_REQUIRED", { provider: s.provider, reason: "LOGIN_REQUIRED", page_generation: String(s.pageGeneration) });
                else if (code === GarpErrorCode.PROVIDER_RATE_LIMITED)
                    await this.service.commitSessionEvent(s, "PROVIDER_RATE_LIMITED", { provider: s.provider, retry_after_ms: "0", page_generation: String(s.pageGeneration) });
                else
                    await this.service.commitSessionEvent(s, "PROVIDER_ERROR", { provider: s.provider, code, message: x.error || "Provider error", retryable: !!x.retryable, prompt_request_id: r.requestId, page_generation: String(s.pageGeneration) });
                await this.failCandidate(r, code, x.error);
                return;
            }
            garpDebug(1, "ObserveGeneration state", {
                request_id: r.requestId,
                session_id: s.sessionId,
                iteration,
                message_count: x.message_count ?? 0,
                message_changed: !!x.message_changed,
                streaming: !!x.streaming,
                done: !!x.done,
                continuation_required: !!x.continuation_required,
                authoritative_generation_started: !!x.authoritative_generation_started,
                authoritative_completion: !!x.authoritative_completion,
                page_url: x.page_url || "",
            });
            const count = Number(x.message_count || 0);
            const text = String(x.text ?? "");
            const allObserved = Array.isArray(x.messages) && x.messages.length
                ? x.messages
                : text.trim().length > 0
                    ? [{ message_id: x.message_id || null, text }]
                    : [];
            const observedMessages =
                allObserved.slice(Number(r.baselineMessageCount || 0));

            r.lastPageGeneration = s.pageGeneration;
            r.actorInstance = s.actorInstance;

            if (!r.responseStarted && observedMessages.length > 0) {
                r.responseStarted = true;
                r.state = PromptState.GENERATING;
            }

            for (const observed of observedMessages) {
                if (!r.responseStarted)
                    continue;

                const mid = observed.message_id || r.messageOrder[0] || uuid();
                const observedText = String(observed.text ?? "");
                const m = r.ensureMessage(mid);
                if (!m.started) {
                    m.started = true;
                    await this.emit(r, "GENERATION_STARTED", { prompt_request_id: r.requestId, message_id: mid, revision: "0", page_generation: String(s.pageGeneration) });
                }
                const delta = m.apply(observedText);
                if (delta) {
                    if (byteLength(m.content) > GARP_MAX_RESPONSE_SIZE) {
                        await this.failCandidate(r, GarpErrorCode.RESPONSE_TOO_LARGE, "Response exceeds max_response_size");
                        return;
                    }
                    if (byteLength(observedText) > GARP_MAX_GENERATION_BUFFER_MB * 1024 * 1024) {
                        await this.failCandidate(r, GarpErrorCode.GENERATION_BUFFER_LIMIT, "Generation buffer limit exceeded");
                        return;
                    }
                    r.partial = true;
                    stable = 0;
                    await this.emit(r, "GENERATION_DELTA", { prompt_request_id: r.requestId, message_id: m.messageId, revision: delta.revision, delta: delta.delta, mode: delta.mode, page_generation: String(s.pageGeneration) });
                }
            }
            const terminalCandidate = r.responseStarted && x.done === true && x.streaming === false && x.continuation_required !== true && count > 0 && text.trim().length > 0;
            if (terminalCandidate) {
                if (stableMessageCount === count && stableText === text) {
                    stable++;
                } else {
                    stableMessageCount = count;
                    stableText = text;
                    stable = 1;
                }
            } else {
                stable = 0;
                stableMessageCount = null;
                stableText = null;
            }
            await this.emit(r, "GENERATION_PROGRESS", { prompt_request_id: r.requestId, message_count: count, page_generation: String(s.pageGeneration) });

            r.lastMessageCount = count;
            r.lastMessageText = text;

            if (x.continuation_required) {
                await this.handleContinuationRequired(r, s, x);
                return;
            }
            if (terminalCandidate && stable >= 2) {
                await this.completeCandidate(r, s, x);
                return;
            }
            await sleep(500);
        }
    }
    async handleContinuationRequired(r, s, x) {
        if (r.cancelAccepted) {
            this.startCancellationResolution(r, s);
            return;
        }
        if (r.maxContinuations === 0) {
            await this.failCandidate(r, GarpErrorCode.CONTINUATION_NOT_ALLOWED, "Continuation is disabled");
            return;
        }
        if (r.continuationCount >= r.maxContinuations) {
            await this.failCandidate(r, GarpErrorCode.CONTINUATION_LIMIT_REACHED, "Continuation limit reached");
            return;
        }
        if (x.continuation_supported === false && !x.continuation_available) {
            await this.failCandidate(r, GarpErrorCode.CONTINUATION_NOT_AVAILABLE, "Continuation unavailable");
            return;
        }
        r.state = PromptState.WAITING_CONTINUATION;
        r.continuationWaitDeadline = monotonicNow() + Number(GARP_DEFAULT_CONTINUATION_WAIT_MS);
        const epoch = ++r.timeoutEpoch;
        await this.emit(r, "CONTINUATION_REQUIRED", { prompt_request_id: r.requestId, continuation_count: r.continuationCount, max_continuations: r.maxContinuations, page_generation: String(s.pageGeneration) });
        this.scheduleTimer(r, r.continuationWaitDeadline, epoch, GarpErrorCode.CONTINUATION_TIMEOUT, "Continuation timeout");
        if (r.options.auto_continue === true)
            this.autoContinue(r, s);
    }
    async autoContinue(r, s) {
        try {
            const reserved = await this.reserveContinuation(r, s, "auto");
            if (reserved)
                await this.runContinuation(r, s, reserved.epoch);
        }
        catch (_) { }
    }
    async reserveContinuation(r, s, source) {
        return s.enqueue(`continue:${source}`, () => {
            if (r.terminalCommitted || r.state !== PromptState.WAITING_CONTINUATION)
                return source === "auto" ? null : Promise.reject(new GarpError(GarpErrorCode.PROMPT_NOT_ACTIVE, "Prompt is not waiting for continuation"));
            if (r.continuationCount >= r.maxContinuations)
                throw new GarpError(GarpErrorCode.CONTINUATION_LIMIT_REACHED, "Continuation limit reached");
            const epoch = ++r.continuationEpoch;
            r.state = PromptState.SUBMITTING;
            return { epoch };
        });
    }
    async continuePrompt(connection, sid, pid) {
        const s = this.sessionManager.get(sid), r = this.getForSession(sid, pid);
        if (r.terminal)
            throw new GarpError(GarpErrorCode.PROMPT_ALREADY_TERMINAL, "Prompt is terminal");
        if (r.state !== PromptState.WAITING_CONTINUATION)
            throw new GarpError(GarpErrorCode.PROMPT_NOT_ACTIVE, "Prompt is not waiting for continuation");
        if (s.ownerConnection && s.ownerConnection !== connection)
            throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
        const reserved = await this.reserveContinuation(r, s, "explicit");
        if (!reserved)
            throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Continuation reservation lost");
        this.runContinuation(r, s, reserved.epoch).catch(e => this.failCandidate(r, e?.code || GarpErrorCode.PROVIDER_ERROR, e?.message || String(e), e));
    }
    async runContinuation(r, s, epoch) {
        const result = await this.service.callChild(s, "ContinueGeneration", { provider: s.provider, prompt_request_id: r.requestId, continuation_epoch: epoch, reason: "provider_length_limit" });
        if (r.cancelAccepted || r.terminalCommitted || epoch !== r.continuationEpoch)
            return;
        if (result.error)
            throw this.errorFromChild(result);
        if (!result.provider_submission_verified)
            throw new GarpError(GarpErrorCode.SUBMISSION_FAILED, "Continuation submission was not positively verified");
        r.continuationCount++;
        r.state = PromptState.GENERATING;
        await this.emit(r, "CONTINUATION_SUBMITTED", { prompt_request_id: r.requestId, page_generation: String(s.pageGeneration), continuation_count: r.continuationCount, strategy: result.strategy || "provider_native_send" });
        this.observe(r).catch(e => this.failCandidate(r, e?.code || GarpErrorCode.PROVIDER_ERROR, e?.message || String(e), e));
    }
    async cancel(connection, sid, pid) {
        const s = this.sessionManager.get(sid), r = this.getForSession(sid, pid);
        if (s.ownerConnection && s.ownerConnection !== connection)
            throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Connection does not own session");
        if (r.terminal)
            throw new GarpError(GarpErrorCode.PROMPT_ALREADY_TERMINAL, "Prompt is terminal");
        if (r.state === PromptState.CANCELLING)
            throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "Cancellation already in progress");
        if (!ACTIVE.has(r.state))
            throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, `Cannot cancel from ${r.state}`);
        r.cancelAccepted = true;
        r.state = PromptState.CANCELLING;
        r.cancelEpoch++;
        r.continuationEpoch++;
        await s.enqueue("cancel-accept", () => {
            if (s.state === "BUSY")
                s.transition("RECOVERING");
        });
        this.startCancellationResolution(r, s);
        return r;
    }
    startCancellationResolution(r, s) {
        this.resolveCancellationStep(r, s).catch(e => this.failCandidate(r, GarpErrorCode.RECOVERY_FAILED, e.message, e));
    }
    async resolveCancellationStep(r, s) {
        const deadline = monotonicNow() + 300000;
        let issued = false;
        const epoch = r.cancelEpoch;
        while (monotonicNow() < deadline && !r.terminalCommitted && epoch === r.cancelEpoch) {
            try {
                if (!issued) {
                    issued = true;
                    const opEpoch = r.providerOperationEpoch + 1;
                    r.providerOperationEpoch = opEpoch;
                    await this.service.callChild(s, "CancelGeneration", { provider: s.provider, prompt_request_id: r.requestId, provider_operation_epoch: opEpoch });
                }
                const state = await this.service.callChild(s, "InspectProviderState", { provider: s.provider, prompt_request_id: r.requestId, previous_message_count: r.lastMessageCount, previous_message_text: r.lastMessageText, provider_operation_epoch: r.providerOperationEpoch });
                if (state.streaming === false && state.authoritative_cessation === true) {
                    r.cancellationVerified = true;
                    await this.cancelCandidate(r, s);
                    return;
                }
                if (state.streaming === false && state.authoritative_completion === true && r.responseStarted) {
                    await this.completeCandidate(r, s, state);
                    return;
                }
            }
            catch (e) {
                if (![GarpErrorCode.STALE_ACTOR, GarpErrorCode.NAVIGATION_DRIFT, GarpErrorCode.TAB_UNAVAILABLE].includes(e?.code) && e?.code !== GarpErrorCode.PROVIDER_ERROR) { }
            }
            await sleep(250);
        }
        if (!r.terminalCommitted)
            await this.failCandidate(r, GarpErrorCode.RECOVERY_FAILED, "Cancellation state could not be authoritatively established");
    }
    currentFencing(r, s) {
        return { session_id: s.sessionId, provider: s.provider, prompt_request_id: r.requestId, page_generation: s.pageGeneration, actor_instance: s.actorInstance, message_id: r.messageOrder[0] || null, fencing_epoch: r.fencingEpoch };
    }
    async completeCandidate(r, s, result) {
        return s.enqueue("terminal-completed", () => this.commitTerminalCandidate({ kind: "COMPLETED", request: r, session: s, fencing: this.currentFencing(r, s), result }));
    }
    async cancelCandidate(r, s) {
        return s.enqueue("terminal-cancelled", () => this.commitTerminalCandidate({ kind: "CANCELLED", request: r, session: s, fencing: this.currentFencing(r, s) }));
    }
    failCandidate(r, code, message, error = null) {
        const s = this.sessionManager.sessions.get(r.sessionId);
        if (!s || r.terminalCommitted)
            return Promise.resolve(false);
        garpError("prompt failure candidate", {
            request_id: r.requestId,
            session_id: r.sessionId,
            provider: r.provider,
            state: r.state,
            code,
            message,
            partial: r.contentCommitted,
            stack: error?.stack || null,
        });
        const c = { kind: "FAILED", request: r, session: s, fencing: this.currentFencing(r, s), code, message, partial: r.contentCommitted };
        return s.enqueue(`terminal-failed:${code}`, () => this.commitTerminalCandidate(c));
    }
    async commitTerminalCandidate(c) {
        const r = c.request, s = c.session;
        garpDebug(1, "terminal candidate", {
            request_id: r.requestId,
            session_id: s.sessionId,
            kind: c.kind,
            state: r.state,
            code: c.code || null,
        });
        if (r.terminalCommitted || s.activeRequestId !== r.requestId)
            return false;
        if (c.fencing.provider !== s.provider || c.fencing.prompt_request_id !== r.requestId)
            return false;
        if (c.kind !== "FAILED" && (!c.fencing.actor_instance || c.fencing.actor_instance !== s.actorInstance || c.fencing.page_generation !== s.pageGeneration))
            return false;
        if (r.timeoutTimer) {
            try {
                r.timeoutTimer.cancel();
            }
            catch (_) { }
            r.timeoutTimer = null;
        }
        r.terminalCommitted = true;
        r.completedAt = monotonicNow();
        r.partial = r.partial || r.contentCommitted || !!c.partial;
        const messages = r.messageOrder.map(id => { const m = r.messages.get(id); return { message_id: m.messageId, revision: String(m.revision), response: m.content }; });
        if (c.kind === "COMPLETED") {
            r.state = PromptState.COMPLETED;
            s.clearActivePrompt();
            s.lastMessageId = r.messageOrder[0] || null;
            s.lastMessageText = r.aggregateContent();
            s.lastMessageCount = Math.max(s.lastMessageCount, r.lastMessageCount);
            const payload = messages.length === 1 ? { prompt_request_id: r.requestId, message_id: messages[0].message_id, revision: messages[0].revision, response: messages[0].response, page_generation: String(s.pageGeneration) } : { prompt_request_id: r.requestId, messages, page_generation: String(s.pageGeneration) };
            this._emitNow(r, s, "GENERATION_COMPLETED", payload);
        }
        else if (c.kind === "CANCELLED") {
            r.state = PromptState.CANCELLED;
            s.clearActivePrompt();
            const payload = messages.length === 1 ? { prompt_request_id: r.requestId, message_id: messages[0].message_id, revision: messages[0].revision, cancel_verified: true, partial: r.partial, response: messages[0].response, page_generation: String(s.pageGeneration) } : { prompt_request_id: r.requestId, cancel_verified: true, partial: r.partial, messages, page_generation: String(s.pageGeneration) };
            this._emitNow(r, s, "GENERATION_CANCELLED", payload);
        }
        else {
            r.state = PromptState.FAILED;
            r.error = { code: c.code, message: c.message };
            s.activeRequestId = null;
            s.generationState = "IDLE";
            if (c.code === GarpErrorCode.PROVIDER_AUTH_REQUIRED)
                s.state = "AUTH_REQUIRED";
            else if (c.code === GarpErrorCode.PROVIDER_RATE_LIMITED)
                s.state = "RATE_LIMITED";
            else if ([GarpErrorCode.NAVIGATION_DRIFT, GarpErrorCode.PROVIDER_UNAVAILABLE, GarpErrorCode.RESPONSE_TOO_LARGE, GarpErrorCode.GENERATION_BUFFER_LIMIT, GarpErrorCode.RECOVERY_FAILED].includes(c.code))
                s.state = "RECOVERING";
            else if (c.code === GarpErrorCode.EVENT_QUEUE_OVERFLOW)
                s.state = "FAILED";
            else
                s.state = s.state === "CLOSED" ? "CLOSED" : "READY";
            const payload = messages.length === 1 ? { prompt_request_id: r.requestId, error: r.error, partial: r.partial, response: messages[0].response || null, page_generation: String(s.pageGeneration) } : { prompt_request_id: r.requestId, error: r.error, partial: r.partial, messages, page_generation: String(s.pageGeneration) };
            this._emitNow(r, s, "GENERATION_FAILED", payload);
        }
        return true;
    }
    async handleNavigationDrift(r, s, error) {
        if (r.terminalCommitted)
            return;
        s.state = "RECOVERING";
        await this.emit(r, "NAVIGATION_DRIFT", { page_generation: String(s.pageGeneration), reason: error?.reason || "DOCUMENT_REPLACED" });
        await this.failCandidate(r, GarpErrorCode.NAVIGATION_DRIFT, "Navigation drift invalidated active prompt");
        this.service.recoverSession(s, "DOCUMENT_REPLACED").catch(() => { });
    }
    async abortForSessionReset(s, reason) {
        const id = s.activeRequestId;
        if (!id)
            return;
        const r = this.requests.get(id);
        if (!r || r.terminalCommitted)
            return;
        await this.failCandidate(r, GarpErrorCode.RECOVERY_FAILED, reason === "SESSION_CLOSE" ? "Session closed while prompt was active" : "Prompt invalidated by RESET_SESSION");
        this.service.callChild(s, "CancelGeneration", { provider: s.provider, prompt_request_id: id }).catch(() => { });
    }
    unsubscribeConnection(connection) {
        let removed = 0;
        for (const [requestId, subscribers] of this.subscribers) {
            if (subscribers.delete(connection))
                removed++;
            if (subscribers.size === 0)
                this.subscribers.delete(requestId);
        }
        garpDebug(1, "connection unsubscribed from requests", {
            removed,
            remaining_request_subscriptions: this.subscribers.size,
        });
        return removed;
    }
    errorFromChild(result) {
        return new GarpError(result.code || GarpErrorCode.PROVIDER_ERROR, result.error || "Provider operation failed", { retryable: !!result.retryable });
    }
    getResponse(r) {
        if (!r.terminal)
            throw new GarpError(GarpErrorCode.RESPONSE_NOT_READY, "The response is not terminally available");
        if (r.messageOrder.length === 1)
            return { success: true, state: r.state, partial: r.partial, response: r.messages.get(r.messageOrder[0]).content || null, ...(r.state === "FAILED" ? { error: r.error } : {}) };
        return { success: true, state: r.state, partial: r.partial, messages: r.messageOrder.map(id => { const m = r.messages.get(id); return { message_id: m.messageId, revision: String(m.revision), response: m.content }; }), ...(r.state === "FAILED" ? { error: r.error } : {}) };
    }
    prune(retentionMs) {
        const n = monotonicNow();
        for (const [id, r] of this.requests)
            if (r.terminalCommitted && r.completedAt !== null && n - r.completedAt > retentionMs) {
                this.requests.delete(id);
                this.subscribers.delete(id);
            }
    }
}

