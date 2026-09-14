export class GarpRequest {
  constructor(requestId, sessionId, prompt, options = {}) {
    this.requestId = requestId;
    this.sessionId = sessionId;
    this.prompt = prompt;
    this.options = options;
    this.state = "SUBMITTING";
    this.messageId = null;
    this.sequence = 0;
    this.pageGeneration = 0;
    this.text = "";
    this.lastText = "";
    this.lastMessageCount = 0;
    this.startedAt = Date.now();
    this.completedAt = null;
    this.continuationCount = 0;
    this.lastEventTime = this.startedAt;
    this.error = null;
    this.responseStarted = false;
  }

  nextSequence() {
    this.sequence += 1;
    return this.sequence;
  }

  snapshot() {
    return {
      request_id: this.requestId,
      session_id: this.sessionId,
      state: this.state,
      message_id: this.messageId,
      sequence: this.sequence,
      page_generation: this.pageGeneration,
      content: this.text,
      continuation_count: this.continuationCount,
      started_at: this.startedAt,
      completed_at: this.completedAt,
      ...(this.error ? { error: this.error } : {}),
    };
  }
}
