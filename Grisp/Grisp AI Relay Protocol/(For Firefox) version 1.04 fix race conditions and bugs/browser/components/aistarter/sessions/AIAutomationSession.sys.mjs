import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

export class AIAutomationSession {
  constructor({ sessionId, provider, tabId, conversationId = null, pageGeneration = 1 }) {
    this.sessionId = sessionId;
    this.provider = provider;
    this.model = null;
    this.tabId = tabId;
    this.conversationId = conversationId;
    this.pageGeneration = pageGeneration;
    this.state = "NEW";
    this.inputState = "UNKNOWN";
    this.generationState = "IDLE";
    this.lastRequestId = null;
    this.lastMessageId = null;
    this.lastMessageText = "";
    this.lastMessageCount = 0;
    this.activeRequestId = null;
    this.pageURL = "";
  }

  assertIdle() {
    if (this.activeRequestId) {
      throw new GarpError(GarpErrorCode.SESSION_BUSY, "Session already has an active prompt", {
        provider: this.provider,
        state: "BUSY",
      });
    }
  }

  markPageGeneration(value, url = "") {
    const numeric = Number(value);
    if (Number.isInteger(numeric) && numeric > this.pageGeneration) {
      this.pageGeneration = numeric;
    }
    if (url) this.pageURL = url;
  }

  snapshot() {
    return {
      session_id: this.sessionId,
      provider: this.provider,
      model: this.model,
      tab_id: this.tabId,
      conversation_id: this.conversationId,
      page_generation: this.pageGeneration,
      input_ready: this.inputState === "READY",
      input_state: this.inputState,
      generation_state: this.generationState,
      last_request_id: this.lastRequestId,
      last_message_id: this.lastMessageId,
      last_message_count: this.lastMessageCount,
      url: this.pageURL,
      state: this.state,
    };
  }
}
