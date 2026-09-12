import { ProviderRegistry } from "../providers/ProviderRegistry.sys.mjs";

const providers = new ProviderRegistry();

export class AIAutomationChild extends JSWindowActorChild {
  constructor() {
    super();
    this.lastInjectedPrompt = "";
    this.lastObservedMessageText = "";
  }

  async receiveMessage(message) {
    try {
      switch (message.name) {
        case "GARP:PrepareSession":
          return this.prepareSession(message.data);
        case "GARP:InspectReady":
          return this.inspectReady(message.data);
        case "GARP:CaptureSnapshot":
          return this.captureSnapshot(message.data);
        case "GARP:InjectPrompt":
          return await this.injectPrompt(message.data);
        case "GARP:ObserveGeneration":
          return this.observeGeneration(message.data);
        case "GARP:ContinueGeneration":
          return await this.continueGeneration(message.data);
        case "GARP:CancelGeneration":
          return this.cancelGeneration(message.data);
        case "GARP:InspectProviderState":
          return this.inspectProviderState(message.data);
        default:
          return { error: `Unknown child operation: ${message.name}`, code: "PROTOCOL_ERROR" };
      }
    } catch (error) {
      dump(`AIAutomationChild GARP ERROR: ${error.message}\n${error.stack || ""}\n`);
      return { error: error.message, code: error.code || "INTERNAL_ERROR" };
    }
  }

  getAdapter(providerName) {
    const adapter = providers.get(providerName);
    if (!adapter) throw Object.assign(new Error(`Provider not found: ${providerName}`), { code: "PROVIDER_NOT_FOUND" });
    return adapter;
  }

  prepareSession(data) {
    const adapter = this.getAdapter(data.provider);
    const inspection = adapter.inspect(this.document);
    return {
      provider: adapter.name,
      adapter_version: adapter.adapter_version,
      selector_strategy_version: adapter.selector_strategy_version,
      supported_features: [...adapter.supported_features],
      ...inspection,
      url: this.document.location?.href || "",
    };
  }

  inspectReady(data) {
    const adapter = this.getAdapter(data.provider);
    const inspection = adapter.inspect(this.document);
    return {
      state: inspection.authenticated === false ? "AUTH_REQUIRED" :
        inspection.rate_limited ? "RATE_LIMITED" :
        inspection.input_ready ? "READY" : "NOT_READY",
      ...inspection,
    };
  }

  responseNodes(adapter) {
    const nodes = adapter.responseNodes(this.document) || [];
    return Array.from(nodes).filter(node => node && typeof node.textContent === "string");
  }

  captureSnapshot(data) {
    const adapter = this.getAdapter(data.provider);
    const nodes = this.responseNodes(adapter);
    const last = nodes.length ? nodes[nodes.length - 1].textContent.trim() : "";
    this.lastObservedMessageText = last;
    return {
      provider: adapter.name,
      url: this.document.location?.href || "",
      input_ready: !!adapter.input(this.document),
      authenticated: adapter.isAuthenticated(this.document),
      rate_limited: adapter.isRateLimited(this.document),
      last_message_count: nodes.length,
      last_message_text: last,
    };
  }

  async injectPrompt(data) {
    const adapter = this.getAdapter(data.provider);
    const input = adapter.input(this.document);
    if (!input) return { error: "Input not ready", code: "INPUT_NOT_READY", state: "NOT_READY" };
    if (!adapter.isAuthenticated(this.document)) return { error: "Provider authentication required", code: "AUTH_REQUIRED", state: "AUTH_REQUIRED" };
    if (adapter.isRateLimited(this.document)) return { error: "Provider rate limit detected", code: "PROVIDER_RATE_LIMIT", state: "RATE_LIMITED" };

    this.lastInjectedPrompt = String(data.prompt || "").trim();
    const result = await adapter.inject(input, this.lastInjectedPrompt);
    const submit = result?.submit_method ? result : await adapter.submit(input, this.document);
    if (submit?.submit_method === "not_available") {
      return { error: "Prompt submission method unavailable", code: "SUBMIT_FAILED", state: "SUBMITTING" };
    }
    return { status: "injected", input_method: "dom_event", submit_method: submit.submit_method };
  }

  continuationButton(adapter) {
    return adapter.findContinueButton(this.document);
  }

  observeGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const inspection = adapter.inspect(this.document);
    const nodes = this.responseNodes(adapter);
    const last = nodes.length ? nodes[nodes.length - 1].textContent.trim() : "";
    const continueButton = this.continuationButton(adapter);
    const continuationRequired = !!continueButton;

    if (inspection.authenticated === false) return { error: "Provider authentication required", code: "AUTH_REQUIRED", state: "AUTH_REQUIRED" };
    if (inspection.rate_limited) return { error: "Provider rate limit detected", code: "PROVIDER_RATE_LIMIT", state: "RATE_LIMITED" };

    return {
      text: last,
      done: !inspection.streaming && !continuationRequired,
      continued: false,
      continuation_required: continuationRequired,
      continuation_reason: continuationRequired ? "provider_length_limit" : null,
      message_count: nodes.length,
      message_changed: nodes.length > Number(data.previous_message_count || 0),
      message_id_hint: nodes.length > Number(data.previous_message_count || 0) ? `dom-message-${nodes.length}` : null,
      streaming: inspection.streaming,
      provider_state: inspection.provider_state,
      page_url: this.document.location?.href || "",
    };
  }

  async continueGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const button = this.continuationButton(adapter);
    if (!button) return { error: "Continuation button not found", code: "CONTINUATION_FAILED" };
    button.focus();
    button.click();
    return { status: "continued", reason: data.reason || "provider_length_limit" };
  }

  cancelGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const stopped = adapter.cancel(this.document);
    return { state: stopped ? "CANCEL_REQUESTED" : "CANCEL_UNAVAILABLE", cancelled: stopped };
  }

  inspectProviderState(data) {
    const adapter = this.getAdapter(data.provider);
    return adapter.inspect(this.document);
  }
}
