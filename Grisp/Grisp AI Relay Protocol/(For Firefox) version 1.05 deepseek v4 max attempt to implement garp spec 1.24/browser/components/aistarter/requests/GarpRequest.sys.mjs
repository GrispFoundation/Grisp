// Prompt lifecycle. §48.

export const PromptState = Object.freeze({
  PENDING: "PENDING",
  SUBMITTING: "SUBMITTING",
  GENERATING: "GENERATING",
  WAITING_CONTINUATION: "WAITING_CONTINUATION",
  CANCELLING: "CANCELLING",
  COMPLETED: "COMPLETED",
  FAILED: "FAILED",
  CANCELLED: "CANCELLED",
});

export class GarpRequest {
  constructor(requestId, sessionId, prompt, options = {}) {
    this.requestId = requestId;
    this.sessionId = sessionId;
    this.prompt = prompt;
    this.options = options;
    this.promptState = PromptState.PENDING;
    this.messageId = null;
    this.pageGeneration = 0n;
    this.text = "";
    this.lastText = "";
    this.lastMessageCount = 0;
    this.revision = 0n;
    this.startedAt = Date.now();
    this.completedAt = null;
    this.continuationCount = 0;
    this.maxContinuations = Number(options.max_continuations ?? 0) | 0;
    this.autoContinue = options.auto_continue === true;
    this.timeoutMs = BigInt(options.timeout_ms ?? "0");
    this.error = null;
    this.responseStarted = false;
    this.subscribers = new Set();
    this._hasCommittedContent = false;
    this._finished = false;
  }

  isTerminal() {
    return (
      this.promptState === PromptState.COMPLETED ||
      this.promptState === PromptState.FAILED ||
      this.promptState === PromptState.CANCELLED
    );
  }

  hasCommittedContent() { return this._hasCommittedContent; }

  markContentCommitted() { this._hasCommittedContent = true; }

  snapshot() {
    return {
      prompt_request_id: this.requestId,
      state: this.promptState,
      message_id: this.messageId,
      revision: String(this.revision),
      page_generation: String(this.pageGeneration),
      content: this.text,
      continuation_count: this.continuationCount,
      started_at: this.startedAt,
      completed_at: this.completedAt,
      error: this.error,
    };
  }
}