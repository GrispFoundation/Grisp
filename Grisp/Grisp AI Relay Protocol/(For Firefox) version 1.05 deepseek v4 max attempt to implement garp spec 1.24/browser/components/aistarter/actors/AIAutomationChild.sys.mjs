// browser/components/aistarter/actors/AIAutomationChild.sys.mjs
//
// GARP/1.24 child actor.
//
// This actor is the browser-side half of the GARP/1.24 provider bridge.
// It receives GARP:<Operation> queries from AIAutomationService (parent) via
// the AIAutomation JSWindowActor pair and returns provider observations.
//
// Fencing (GARP/1.24 §91, §92, §168):
//   Every query carries a `_fencing` context supplied by the parent:
//       { session_id, page_generation, actor_instance, provider }
//   Every state-bearing reply echoes the same fencing context back so that
//   the parent can discard results whose page_generation or actor_instance
//   no longer matches the session's authoritative values. The child does not
//   itself decide whether a result is stale; it only labels results
//   faithfully so the parent can apply the discard rule deterministically.
//
// Provider adapters (GARP/1.24 §119, §120, §167):
//   All provider-specific selector and DOM logic lives in
//   ../providers/*.sys.mjs. This actor contains no provider-specific
//   selectors and no provider-specific branching.
//
// Reference:
//   GARP/1.24 §10, §11, §42, §55, §56, §57, §60, §61, §69, §70, §71, §91,
//   §92, §167, §168.

import { ProviderRegistry } from "../providers/ProviderRegistry.sys.mjs";

const providers = new ProviderRegistry();

export class AIAutomationChild extends JSWindowActorChild {
  constructor() {
    super();

    // Last prompt text this actor actually injected. Retained so that
    // ObserveGeneration can distinguish "the DOM the adapter sees now" from
    // "the response that the adapter's responseNodes() reports".
    //
    // The prompt string is opaque (GARP/1.24 §49.1): it MUST NOT be trimmed,
    // normalized, or otherwise modified by the child. We store the exact
    // value supplied by the parent.
    this.lastInjectedPrompt = "";

    // Last observed message text. Used purely as a local cache to help
    // ObserveGeneration report stable vs. changed state on the current page;
    // it is NOT authoritative protocol state.
    this.lastObservedMessageText = "";

    // Instance identity for this actor. Per §92, actor_instance is unique
    // for the actor's lifetime. A replacement of this actor produces a new
    // instance because the constructor runs again in a new JSWindowActorChild.
    this.actorInstance =
      (globalThis.crypto?.randomUUID?.() ??
        `${Date.now()}-${Math.random().toString(16).slice(2)}`);
  }

  /**
   * Return the fencing block supplied by the parent, or a deterministic
   * empty shape when the parent did not provide one.
   *
   * The empty shape intentionally uses null values so that a caller cannot
   * mistake an absent fencing context for a valid one.
   */
  fencingFrom(data) {
    const f = data?._fencing || {};
    return {
      session_id: f.session_id ?? null,
      page_generation: f.page_generation ?? null,
      actor_instance: f.actor_instance ?? null,
      provider: f.provider ?? null,
    };
  }

  /**
   * Overlay the fencing context onto a reply payload so the parent can
   * perform §91 fencing discard.
   *
   * The child additionally reports its own actor_instance so that the parent
   * can detect actor replacement even if it did not supply a fencing block
   * (for example, during a defensive recovery query).
   */
  withFencing(payload, fencing) {
    const out = payload && typeof payload === "object" ? payload : {};
    return {
      ...out,
      _fencing: {
        session_id: fencing.session_id,
        page_generation: fencing.page_generation,
        // The actor_instance the parent believes is authoritative for this
        // session; echoed back unmodified so a mismatch on the parent is
        // detected as a stale actor.
        parent_actor_instance: fencing.actor_instance,
        // The actor_instance actually executing this query.
        child_actor_instance: this.actorInstance,
        provider: fencing.provider,
      },
    };
  }

  async receiveMessage(message) {
    const fencing = this.fencingFrom(message?.data);

    try {
      switch (message.name) {
        case "GARP:PrepareSession":
          return this.withFencing(
            this.prepareSession(message.data),
            fencing
          );

        case "GARP:InspectReady":
          return this.withFencing(
            this.inspectReady(message.data),
            fencing
          );

        case "GARP:CaptureSnapshot":
          return this.withFencing(
            this.captureSnapshot(message.data),
            fencing
          );

        case "GARP:InjectPrompt":
          return this.withFencing(
            await this.injectPrompt(message.data),
            fencing
          );

        case "GARP:ObserveGeneration":
          return this.withFencing(
            this.observeGeneration(message.data),
            fencing
          );

        case "GARP:ContinueGeneration":
          return this.withFencing(
            await this.continueGeneration(message.data),
            fencing
          );

        case "GARP:CancelGeneration":
          return this.withFencing(
            this.cancelGeneration(message.data),
            fencing
          );

        case "GARP:InspectProviderState":
          return this.withFencing(
            this.inspectProviderState(message.data),
            fencing
          );

        default:
          return this.withFencing(
            {
              error: `Unknown child operation: ${message.name}`,
              code: "UNKNOWN_MESSAGE_TYPE",
            },
            fencing
          );
      }
    } catch (error) {
      dump(
        `AIAutomationChild GARP/1.24 ERROR: ${error?.message || String(error)}\n${error?.stack || ""}\n`
      );

      return this.withFencing(
        {
          error: error?.message || String(error),
          code: error?.code || "PROVIDER_ERROR",
          details: error?.details || undefined,
          state: error?.state || "FAILED",
        },
        fencing
      );
    }
  }

  /**
   * Resolve a provider adapter by name.
   *
   * Unknown providers surface as PROVIDER_UNAVAILABLE (GARP/1.24 §27), which
   * is the correct canonical error for "adapter for the configured provider
   * is not installed" per §22.1's definition of provider unavailability.
   */
  getAdapter(providerName) {
    const adapter = providers.get(providerName);

    if (!adapter) {
      throw Object.assign(
        new Error(`Provider not found: ${providerName}`),
        { code: "PROVIDER_UNAVAILABLE" }
      );
    }

    return adapter;
  }

  // -------------------------------------------------------------------------
  // Provider state inspection
  // -------------------------------------------------------------------------

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

    // §22.1 / §34: readiness MUST NOT be inferred solely from tab existence.
    // The adapter's inspect() is the authoritative source for input_ready,
    // authenticated, and rate_limited.
    return {
      state:
        inspection.authenticated === false
          ? "AUTH_REQUIRED"
          : inspection.rate_limited
          ? "RATE_LIMITED"
          : inspection.input_ready
          ? "READY"
          : "NOT_READY",
      ...inspection,
    };
  }

  inspectProviderState(data) {
    const adapter = this.getAdapter(data.provider);
    return adapter.inspect(this.document);
  }

  // -------------------------------------------------------------------------
  // Response node discovery
  // -------------------------------------------------------------------------

  responseNodes(adapter) {
    const nodes = adapter.responseNodes(this.document) || [];
    return Array.from(nodes).filter(
      node => node && typeof node.textContent === "string"
    );
  }

  captureSnapshot(data) {
    const adapter = this.getAdapter(data.provider);
    const nodes = this.responseNodes(adapter);

    const last = nodes.length
      ? nodes[nodes.length - 1].textContent.trim()
      : "";

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

  // -------------------------------------------------------------------------
  // Prompt injection
  // -------------------------------------------------------------------------

  async injectPrompt(data) {
    const adapter = this.getAdapter(data.provider);
    const input = adapter.input(this.document);

    if (!input) {
      return {
        error: "Input not ready",
        code: "INPUT_VERIFICATION_FAILED",
        state: "NOT_READY",
      };
    }

    if (!adapter.isAuthenticated(this.document)) {
      return {
        error: "Provider authentication required",
        code: "PROVIDER_AUTH_REQUIRED",
        state: "AUTH_REQUIRED",
      };
    }

    if (adapter.isRateLimited(this.document)) {
      return {
        error: "Provider rate limit detected",
        code: "PROVIDER_RATE_LIMITED",
        state: "RATE_LIMITED",
      };
    }

    // §49.1: the prompt string is opaque. Store and inject the exact value
    // supplied by the parent, with no trimming, normalization, or mutation.
    this.lastInjectedPrompt = String(data.prompt ?? "");

    if (!this.lastInjectedPrompt) {
      return {
        error: "Prompt is empty",
        code: "INVALID_ARGUMENT",
        state: "FAILED",
      };
    }

    const result = await adapter.inject(input, this.lastInjectedPrompt);

    if (result?.error) {
      return result;
    }

    const submit = result?.submit_method
      ? result
      : await adapter.submit(input, this.document);

    if (submit?.error) {
      return submit;
    }

    if (submit?.submit_method === "not_available") {
      return {
        error: "Prompt submission method unavailable",
        code: "SUBMISSION_FAILED",
        state: "SUBMITTING",
      };
    }

    // §56: the strategy field reports the input strategy that was actually
    // used. The parent maps this to INPUT_SUBMITTED.strategy.
    const inputStrategy =
      result?.input_method === "contenteditable"
        ? "keyboard_enter"
        : "provider_native_send";

    return {
      status: "injected",
      input_method: result?.input_method || "dom_event",
      input_verified: result?.input_verified !== false,
      input_text_length: Number(
        result?.input_text_length || this.lastInjectedPrompt.length
      ),
      submit_method: submit.submit_method,
      input_strategy: inputStrategy,
    };
  }

  // -------------------------------------------------------------------------
  // Continuation
  // -------------------------------------------------------------------------

  continuationButton(adapter) {
    return adapter.findContinueButton(this.document);
  }

  observeGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const inspection = adapter.inspect(this.document);
    const nodes = this.responseNodes(adapter);

    const last = nodes.length
      ? nodes[nodes.length - 1].textContent.trim()
      : "";

    const continueButton = this.continuationButton(adapter);
    const continuationRequired = !!continueButton;

    if (inspection.authenticated === false) {
      return {
        error: "Provider authentication required",
        code: "PROVIDER_AUTH_REQUIRED",
        state: "AUTH_REQUIRED",
      };
    }

    if (inspection.rate_limited) {
      return {
        error: "Provider rate limit detected",
        code: "PROVIDER_RATE_LIMITED",
        state: "RATE_LIMITED",
      };
    }

    const previousCount = Number(data.previous_message_count || 0);

    return {
      text: last,
      done: !inspection.streaming && !continuationRequired,
      continued: false,
      continuation_required: continuationRequired,
      continuation_reason: continuationRequired
        ? "provider_length_limit"
        : null,
      message_count: nodes.length,
      message_changed: nodes.length > previousCount,
      message_id_hint:
        nodes.length > previousCount
          ? `dom-message-${nodes.length}`
          : null,
      streaming: inspection.streaming,
      provider_state: inspection.provider_state,
      page_url: this.document.location?.href || "",
    };
  }

  async continueGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const button = this.continuationButton(adapter);

    if (!button) {
      return {
        error: "Continuation button not found",
        code: "CONTINUATION_NOT_AVAILABLE",
      };
    }

    button.focus();
    button.click();

    return {
      status: "continued",
      reason: data.reason || "provider_length_limit",
      // Report the strategy actually used so the parent can populate
      // CONTINUATION_SUBMITTED.strategy per §67.
      submit_method: "button_click",
    };
  }

  // -------------------------------------------------------------------------
  // Cancellation
  // -------------------------------------------------------------------------

  cancelGeneration(data) {
    const adapter = this.getAdapter(data.provider);
    const stopped = adapter.cancel(this.document);

    return {
      state: stopped ? "CANCELLING" : "CANCELLING",
      cancelled: stopped,
      // The protocol does not permit the child to declare cancellation
      // terminal on its own. §73 requires positive provider cessation
      // evidence. This reply is a *request* outcome; the parent must obtain
      // authoritative cessation evidence before committing a CANCELLED
      // terminal candidate (see §72.1).
      cessation_verified: false,
    };
  }
}