import { GARP_UINT64_MAX } from "../garp/GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

export class GarpRequest {
  constructor(requestId, sessionId, prompt, options = {}) {
    this.requestId = requestId;
    this.sessionId = sessionId;
    this.prompt = prompt;
    this.options = Object.freeze({ ...options });
    this.state = "PENDING";
    this.messageId = crypto.randomUUID();
    this.revision = 0n;
    this.content = "";
    this.lastObservedText = "";
    this.lastMessageCount = 0;
    this.baselineMessageCount = 0;
    this.baselineMessageText = "";
    this.startedAt = performance?.now?.() ?? Date.now();
    this.completedAt = null;
    this.continuationCount = 0;
    this.maxContinuations = Number(options.max_continuations ?? 8);
    this.continuationWaitDeadline = null;
    this.promptDeadline = null;
    this.responseStarted = false;
    this.partial = false;
    this.terminalCommitted = false;
    this.terminalCandidate = null;
    this.providerOperationEpoch = 0;
    this.continuationEpoch = 0;
    this.cancelAccepted = false;
    this.cancellationVerified = false;
    this.lastPageGeneration = 1n;
    this.actorInstance = null;
    this.provider = null;
    this.error = null;
  }

  get contentCommitted() { return this.partial || this.revision > 0n || this.content.length > 0; }
  get terminal() { return this.state === "COMPLETED" || this.state === "FAILED" || this.state === "CANCELLED"; }

  nextRevision() {
    if (this.revision >= GARP_UINT64_MAX) throw new GarpError(GarpErrorCode.REVISION_GAP, "Message revision overflow");
    this.revision += 1n;
    return this.revision;
  }

  snapshot() {
    return {
      success: true,
      prompt_request_id: this.requestId,
      state: this.state,
      page_generation: String(this.lastPageGeneration),
      message_id: this.messageId,
      revision: String(this.revision),
      continuation_count: this.continuationCount,
      max_continuations: this.maxContinuations,
      partial: this.partial,
      ...(this.error ? { error: this.error } : {}),
    };
  }
}
