import { ProviderRegistry } from "../providers/ProviderRegistry.sys.mjs";
import { garpDebug, garpError } from "../GarpDebug.sys.mjs";
const providers = new ProviderRegistry();
export class AIAutomationChild extends JSWindowActorChild {
    constructor() {
        super();
        this.actorInstance = crypto.randomUUID();
        this.nodeMessageIds = new WeakMap();
        this.cancelContexts = new Map();
        this.lastInjectedPrompt = "";
        this.parentActorInstance = null;
    }
    fence(data) {
        const f = data || {};
        return { session_id: f.session_id ?? null, provider: f.provider ?? null, page_generation: f.page_generation ?? null, prompt_request_id: f.prompt_request_id ?? null, parent_actor_instance: f.parent_actor_instance ?? null, child_actor_instance: this.actorInstance };
    }
    async receiveMessage(message) {
        const data = message.data || {};
        const debugLevel = data.debug_level ?? 0;
        garpDebug(2, "child operation entered", {
            operation: message.name,
            session_id: data.session_id ?? null,
            provider: data.provider ?? null,
            prompt_request_id: data.prompt_request_id ?? null,
            page_generation: data.page_generation ?? null,
            url: this.document?.location?.href || "",
            child_actor_instance: this.actorInstance,
        }, debugLevel);
        try {
            if (data.actor_instance && data.actor_instance !== this.parentActorInstance)
                this.parentActorInstance = data.actor_instance;
            let result;
            switch (message.name) {
                case "GARP:PrepareSession":
                    result = this.prepareSession(data);
                    break;
                case "GARP:InspectReady":
                    result = this.inspectReady(data);
                    break;
                case "GARP:CaptureSnapshot":
                    result = this.captureSnapshot(data);
                    break;
                case "GARP:InjectPrompt":
                    result = await this.injectPrompt(data);
                    break;
                case "GARP:ObserveGeneration":
                    result = this.observeGeneration(data);
                    break;
                case "GARP:ContinueGeneration":
                    result = await this.continueGeneration(data);
                    break;
                case "GARP:CancelGeneration":
                    result = this.cancelGeneration(data);
                    break;
                case "GARP:InspectProviderState":
                    result = this.inspectProviderState(data);
                    break;
                default: result = { error: `Unknown child operation: ${message.name}`, code: "UNKNOWN_MESSAGE_TYPE" };
            }
            garpDebug(2, "child operation completed", {
                operation: message.name,
                session_id: data.session_id ?? null,
                result,
            }, debugLevel);
            return { ...result, fencing: this.fence(data) };
        }
        catch (e) {
            garpError("child operation exception", {
                operation: message.name,
                session_id: data.session_id ?? null,
                provider: data.provider ?? null,
                prompt_request_id: data.prompt_request_id ?? null,
                code: e?.code || null,
                message: e?.message || String(e),
                stack: e?.stack || null,
            });
            return { error: e?.message || String(e), code: e?.code || "PROVIDER_ERROR", details: e?.details, fencing: this.fence(data) };
        }
    }
    adapter(name) {
        const a = providers.get(name);
        if (!a)
            throw Object.assign(new Error(`Provider unavailable: ${name}`), { code: "PROVIDER_UNAVAILABLE" });
        return a;
    }
    prepareSession(d) {
        const a = this.adapter(d.provider), i = a.inspect(this.document);
        return { provider: a.name, adapter_version: a.adapter_version, selector_strategy_version: a.selector_strategy_version, supported_features: [...a.supported_features], input_strategies: a.inputStrategies(this.document), ...i, url: this.document.location?.href || "" };
    }
    inspectReady(d) {
        const a = this.adapter(d.provider), i = a.inspect(this.document);
        return { state: i.authenticated === false ? "AUTH_REQUIRED" : i.rate_limited ? "RATE_LIMITED" : i.input_ready ? "READY" : "NOT_READY", ...i };
    }
    nodes(a) {
        return Array.from(a.responseNodes(this.document) || []).filter(n => n && typeof n.textContent === "string");
    }
    idForNode(n) {
        let id = this.nodeMessageIds.get(n);
        if (!id) {
            id = crypto.randomUUID();
            this.nodeMessageIds.set(n, id);
        }
        return id;
    }
    captureSnapshot(d) {
        const a = this.adapter(d.provider), ns = this.nodes(a), messages = ns.map(n => ({ message_id: this.idForNode(n), text: String(n.textContent || "") }));
        return { provider: a.name, url: this.document.location?.href || "", input_ready: !!a.input(this.document), authenticated: a.isAuthenticated(this.document), rate_limited: a.isRateLimited(this.document), message_count: ns.length, messages, last_message_count: ns.length, last_message_text: messages.length ? messages[messages.length - 1].text : "" };
    }
    async injectPrompt(d) {
        garpDebug(1, "child InjectPrompt begin", {
            session_id: d.session_id,
            provider: d.provider,
            prompt_request_id: d.prompt_request_id,
            prompt_length: String(d.prompt ?? "").length,
            force_focus: !!d.forceFocus,
            simulate_enter: !!d.simulateEnter,
            url: this.document.location?.href || "",
        }, d.debug_level);
        const a = this.adapter(d.provider), input = a.input(this.document);
        garpDebug(1, "provider input lookup", {
            provider: d.provider,
            found: !!input,
            tag: input?.tagName || null,
            id: input?.id || null,
            classes: String(input?.className || ""),
            contenteditable: input?.getAttribute?.("contenteditable") || null,
        }, d.debug_level);
        if (!input)
            return { error: "Input not ready", code: "INPUT_VERIFICATION_FAILED", state: "PREPARING" };
        if (a.isAuthenticated(this.document) === false)
            return { error: "Provider authentication required", code: "PROVIDER_AUTH_REQUIRED", state: "AUTH_REQUIRED" };
        if (a.isRateLimited(this.document))
            return { error: "Provider rate limit detected", code: "PROVIDER_RATE_LIMITED", state: "RATE_LIMITED" };
        this.lastInjectedPrompt = String(d.prompt ?? "");
        if (!this.lastInjectedPrompt)
            return { error: "Prompt is empty", code: "INVALID_ARGUMENT", state: "FAILED" };
        const injected = await a.inject(input, this.lastInjectedPrompt, { forceFocus: !!d.forceFocus, debugLevel: d.debug_level });
        garpDebug(1, "provider inject result", { provider: d.provider, result: injected }, d.debug_level);
        if (injected?.error)
            return injected;
        const submit = await a.submitVerified(input, this.document, { simulateEnter: !!d.simulateEnter, debugLevel: d.debug_level });
        garpDebug(1, "provider submit result", { provider: d.provider, result: submit }, d.debug_level);
        if (submit?.error)
            return submit;
        return { ...injected, ...submit, provider_submission_verified: submit.provider_submission_verified === true, strategy: submit.strategy || "provider_native_send" };
    }
    continuationButton(a) {
        return a.findContinueButton(this.document);
    }
    observeGeneration(d) {
        const a = this.adapter(d.provider), i = a.inspect(this.document), ns = this.nodes(a), messages = ns.map(n => ({ message_id: this.idForNode(n), text: String(n.textContent || "") })), last = messages.length ? messages[messages.length - 1].text : "", button = this.continuationButton(a);
        if (i.authenticated === false)
            return { error: "Provider authentication required", code: "PROVIDER_AUTH_REQUIRED", state: "AUTH_REQUIRED" };
        if (i.rate_limited)
            return { error: "Provider rate limit detected", code: "PROVIDER_RATE_LIMITED", state: "RATE_LIMITED" };
        garpDebug(2, "child ObserveGeneration DOM snapshot", {
            provider: d.provider,
            previous_message_count: Number(d.previous_message_count || 0),
            current_message_count: messages.length,
            last_text_length: last.length,
            streaming: !!i.streaming,
            continuation_button: !!button,
            provider_state: i.provider_state,
            url: this.document.location?.href || "",
        }, d.debug_level);
        const previousCount = Number(d.previous_message_count || 0), previousText = String(d.previous_message_text || ""), changed = messages.length > previousCount || last !== previousText, hasResponse = messages.length > 0 && last.trim().length > 0, done = hasResponse && !i.streaming && !button;
        return { provider: a.name, messages, text: last, done, continuation_required: !!button, continuation_supported: a.supportsContinuation(this.document), continuation_available: !!button, continuation_reason: button ? "provider_length_limit" : null, message_count: messages.length, message_changed: changed, authoritative_generation_started: changed, authoritative_completion: done, provider_state: i.provider_state, streaming: i.streaming, page_url: this.document.location?.href || "" };
    }
    async continueGeneration(d) {
        const a = this.adapter(d.provider);
        if (!a.supportsContinuation(this.document))
            return { error: "Continuation unavailable", code: "CONTINUATION_NOT_AVAILABLE" };
        const b = this.continuationButton(a);
        if (!b)
            return { error: "Continuation button not found", code: "CONTINUATION_NOT_AVAILABLE" };
        b.focus();
        b.click();
        const verified = await a.verifyContinuationSubmission(this.document);
        return { provider_submission_verified: verified, strategy: "provider_native_send" };
    }
    cancelGeneration(d) {
        const a = this.adapter(d.provider), stopped = a.cancel(this.document);
        const pid = d.prompt_request_id || "__session__";
        const ctx = this.cancelContexts.get(pid) || {};
        ctx.issuedAt = Date.now();
        ctx.epoch = d.provider_operation_epoch ?? ctx.epoch ?? 0;
        ctx.requested = stopped === true;
        this.cancelContexts.set(pid, ctx);
        return { cancel_requested: stopped, cancel_verified: false, state: stopped ? "CANCEL_REQUESTED" : "CANCEL_UNAVAILABLE" };
    }
    inspectProviderState(d) {
        const a = this.adapter(d.provider), i = a.inspect(this.document), pid = d.prompt_request_id || "__session__", ctx = this.cancelContexts.get(pid);
        const hasResponse = Number(i.message_count || 0) > 0 && String(i.last_message_text ?? "").trim().length > 0;
        return { ...i, authoritative_cessation: !!ctx && ctx.requested === true && !i.streaming, authoritative_completion: hasResponse && !i.streaming };
    }
}

