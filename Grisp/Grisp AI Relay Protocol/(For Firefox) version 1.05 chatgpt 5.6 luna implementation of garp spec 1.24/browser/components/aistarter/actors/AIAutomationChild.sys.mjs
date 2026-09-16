import { ProviderRegistry } from "../providers/ProviderRegistry.sys.mjs";

const providers = new ProviderRegistry();

export class AIAutomationChild extends JSWindowActorChild {
  constructor() {
    super();
    this.actorInstance = crypto.randomUUID();
    this.lastInjectedPrompt = "";
    this.lastObservedMessageText = "";
  }

  fencing(data) {
    return {
      session_id: data?.session_id ?? null,
      provider: data?.provider ?? null,
      page_generation: data?.page_generation ?? null,
      actor_instance: this.actorInstance,
      prompt_request_id: data?.prompt_request_id ?? null,
    };
  }

  validateFencing(data) {
    if (data?.actor_instance && data.actor_instance !== this.actorInstance) {
      return { error: "STALE_ACTOR", code: "STALE_ACTOR" };
    }
    return null;
  }

  async receiveMessage(message) {
    try {
      const stale = this.validateFencing(message.data);
      if (stale) return stale;
      switch (message.name) {
        case "GARP:PrepareSession": return this.prepareSession(message.data);
        case "GARP:InspectReady": return this.inspectReady(message.data);
        case "GARP:CaptureSnapshot": return this.captureSnapshot(message.data);
        case "GARP:InjectPrompt": return await this.injectPrompt(message.data);
        case "GARP:ObserveGeneration": return this.observeGeneration(message.data);
        case "GARP:ContinueGeneration": return await this.continueGeneration(message.data);
        case "GARP:CancelGeneration": return this.cancelGeneration(message.data);
        case "GARP:InspectProviderState": return this.inspectProviderState(message.data);
        default: return { error: `Unknown child operation: ${message.name}`, code: "UNKNOWN_MESSAGE_TYPE" };
      }
    } catch (error) {
      dump(`AIAutomationChild GARP ERROR: ${error.message}\n${error.stack || ""}\n`);
      return { error: error.message, code: error.code || "PROVIDER_ERROR", details: error.details || undefined };
    }
  }

  getAdapter(providerName) {
    const adapter = providers.get(providerName);
    if (!adapter) throw Object.assign(new Error(`Provider adapter unavailable: ${providerName}`), { code: "PROVIDER_UNAVAILABLE" });
    return adapter;
  }

  result(data, payload) { return { ...payload, fencing: this.fencing(data) }; }

  prepareSession(data) {
    const adapter = this.getAdapter(data.provider);
    const inspection = adapter.inspect(this.document);
    return this.result(data, {
      provider: adapter.name,
      adapter_version: adapter.adapter_version,
      selector_strategy_version: adapter.selector_strategy_version,
      input_strategies: adapter.inputStrategies(this.document),
      supported_features: [...adapter.supported_features],
      ...inspection,
      url: this.document.location?.href || "",
    });
  }

  inspectReady(data) {
    const adapter = this.getAdapter(data.provider);
    return this.result(data, {
      ...adapter.inspect(this.document),
      state: adapter.isAuthenticated(this.document) === false ? "AUTH_REQUIRED" : adapter.isRateLimited(this.document) ? "RATE_LIMITED" : adapter.input(this.document) ? "READY" : "NOT_READY",
    });
  }

  responseNodes(adapter) {
    return Array.from(adapter.responseNodes(this.document) || []).filter(node => node && typeof node.textContent === "string");
  }

  captureSnapshot(data) {
    const adapter = this.getAdapter(data.provider);
    const nodes = this.responseNodes(adapter);
    const last = nodes.length ? nodes[nodes.length - 1].textContent : "";
    this.lastObservedMessageText = last;
    return this.result(data, {
      provider: adapter.name,
      url: this.document.location?.href || "",
      input_ready: !!adapter.input(this.document),
      authenticated: adapter.isAuthenticated(this.document),
      rate_limited: adapter.isRateLimited(this.document),
      last_message_count: nodes.length,
      last_message_text: last,
    });
  }

  async injectPrompt(data) {
    const adapter = this.getAdapter(data.provider);
    const input = adapter.input(this.document);
    if (!input) return this.result(data, { error: "Input not ready", code: "INPUT_VERIFICATION_FAILED", state: "PREPARING" });
    if (!adapter.isAuthenticated(this.document)) return this.result(data, { error: "Provider authentication required", code: "PROVIDER_AUTH_REQUIRED", state: "AUTH_REQUIRED" });
    if (adapter.isRateLimited(this.document)) return this.result(data, { error: "Provider rate limit detected", code: "PROVIDER_RATE_LIMITED", state: "RATE_LIMITED" });
    this.lastInjectedPrompt = String(data.prompt ?? "");
    if (!this.lastInjectedPrompt) return this.result(data, { error: "Prompt is empty", code: "INVALID_ARGUMENT", state: "FAILED" });
    const inputResult = await adapter.inject(input, this.lastInjectedPrompt, { forceFocus: !!data.forceFocus });
    if (inputResult?.error) return this.result(data, inputResult);
    if (data.forceFocus && !inputResult.focus_verified) return this.result(data, { error: "Focus verification failed", code: "INPUT_VERIFICATION_FAILED", state: "FAILED" });
    const submit = await adapter.submitVerified(input, this.document, { simulateEnter: !!data.simulateEnter });
    if (submit?.error) return this.result(data, submit);
    return this.result(data, { ...inputResult, ...submit, provider_submission_verified: submit.provider_submission_verified === true, strategy: submit.strategy || inputResult.strategy || "provider_native_send" });
  }

  continuationButton(adapter) { return adapter.findContinueButton(this.document); }

  observeGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const inspection = adapter.inspect(this.document);
    const nodes = this.responseNodes(adapter);
    const last = nodes.length ? nodes[nodes.length - 1].textContent : "";
    const continueButton = this.continuationButton(adapter);
    if (inspection.authenticated === false) return this.result(data, { error: "Provider authentication required", code: "PROVIDER_AUTH_REQUIRED", state: "AUTH_REQUIRED" });
    if (inspection.rate_limited) return this.result(data, { error: "Provider rate limit detected", code: "PROVIDER_RATE_LIMITED", state: "RATE_LIMITED" });
    const previousCount = Number(data.previous_message_count || 0);
    const messageChanged = nodes.length > previousCount || (last && last !== String(data.previous_message_text || ""));
    const authoritativeStarted = messageChanged;
    const authoritativeCompletion = !inspection.streaming && !!last;
    return this.result(data, {
      provider: adapter.name,
      text: last,
      done: authoritativeCompletion && !continueButton,
      continuation_required: !!continueButton,
      continuation_supported: adapter.supportsContinuation(this.document),
      continuation_available: !!continueButton,
      continuation_reason: continueButton ? "provider_length_limit" : null,
      message_count: nodes.length,
      message_changed: messageChanged,
      authoritative_generation_started: authoritativeStarted,
      authoritative_completion: authoritativeCompletion,
      provider_state: inspection.provider_state,
      streaming: inspection.streaming,
      page_url: this.document.location?.href || "",
    });
  }

  async continueGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    if (!adapter.supportsContinuation(this.document)) return this.result(data, { error: "Continuation is not available", code: "CONTINUATION_NOT_AVAILABLE" });
    const button = this.continuationButton(adapter);
    if (!button) return this.result(data, { error: "Continuation button not found", code: "CONTINUATION_NOT_AVAILABLE" });
    button.focus();
    button.click();
    const verified = await adapter.verifyContinuationSubmission(this.document);
    return this.result(data, { provider_submission_verified: verified, strategy: verified ? "provider_native_send" : "provider_native_send" });
  }

  async cancelGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const stopped = adapter.cancel(this.document);
    return this.result(data, { cancel_requested: stopped, state: stopped ? "CANCEL_REQUESTED" : "CANCEL_UNAVAILABLE" });
  }

  inspectProviderState(data) {
    const adapter = this.getAdapter(data.provider);
    return this.result(data, { ...adapter.inspectProviderExecution(this.document, data) });
  }
}
