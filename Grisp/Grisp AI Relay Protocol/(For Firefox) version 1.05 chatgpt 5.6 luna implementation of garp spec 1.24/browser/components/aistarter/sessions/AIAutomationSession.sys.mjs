import {
  GARP_MAX_EVENT_HISTORY_MEMORY_MB,
  GARP_MAX_QUEUED_EVENTS,
  GARP_UINT64_MAX,
} from "../garp/GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";
import { byteLength, uint64, uuid } from "../garp/GarpUtil.sys.mjs";

const TERMINAL_PROMPT_STATES = new Set(["COMPLETED", "FAILED", "CANCELLED"]);

const VALID_TRANSITIONS = Object.freeze({
  CREATED: new Set(["PREPARING", "FAILED", "CLOSED"]),
  PREPARING: new Set(["READY", "AUTH_REQUIRED", "RATE_LIMITED", "RETRYING", "RECOVERING", "FAILED", "CLOSED"]),
  READY: new Set(["BUSY", "PREPARING", "AUTH_REQUIRED", "RATE_LIMITED", "RECOVERING", "FAILED", "CLOSED"]),
  BUSY: new Set(["READY", "PREPARING", "RETRYING", "AUTH_REQUIRED", "RATE_LIMITED", "RECOVERING", "FAILED", "CLOSED"]),
  AUTH_REQUIRED: new Set(["PREPARING", "FAILED", "CLOSED"]),
  RATE_LIMITED: new Set(["PREPARING", "FAILED", "CLOSED"]),
  RECOVERING: new Set(["READY", "BUSY", "RETRYING", "FAILED", "CLOSED"]),
  RETRYING: new Set(["BUSY", "PREPARING", "FAILED", "CLOSED"]),
  FAILED: new Set(["PREPARING", "CLOSED"]),
  CLOSED: new Set(),
});

export class AIAutomationSession {
  constructor({ sessionId, provider, tabId, pageGeneration = 1n }) {
    this.sessionId = sessionId || uuid();
    this.provider = provider;
    this.model = null;
    this.tabId = tabId;
    this.pageGeneration = BigInt(pageGeneration);
    this.state = "CREATED";
    this.inputState = "UNKNOWN";
    this.generationState = "IDLE";
    this.lastRequestId = null;
    this.lastMessageId = null;
    this.lastMessageText = "";
    this.lastMessageCount = 0;
    this.activeRequestId = null;
    this.pageURL = "";
    this.actorInstance = null;
    this.actorObject = null;
    this.authoritativeProvider = provider;
    this.ownerConnection = null;
    this.eventSequence = 0n;
    this.eventHistory = [];
    this.eventHistoryBytes = 0;
    this.arbiterTail = Promise.resolve();
  }

  static isTerminalPromptState(state) { return TERMINAL_PROMPT_STATES.has(state); }

  enqueue(label, operation) {
    const run = this.arbiterTail.then(async () => operation());
    this.arbiterTail = run.catch(() => {});
    return run;
  }

  transition(nextState) {
    if (nextState === this.state) return;
    if (!VALID_TRANSITIONS[this.state]?.has(nextState)) {
      throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, `Invalid session transition ${this.state} -> ${nextState}`, { state: this.state });
    }
    this.state = nextState;
  }

  assertMutable() {
    if (this.state === "CLOSED") throw new GarpError(GarpErrorCode.SESSION_CLOSED, "Session is closed", { state: "CLOSED" });
  }

  assertIdle() {
    this.assertMutable();
    if (this.activeRequestId) throw new GarpError(GarpErrorCode.SESSION_BUSY, "Session already has an active prompt", { provider: this.provider, state: "BUSY" });
    if (this.state !== "READY") throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, `Session is not READY: ${this.state}`, { state: this.state });
  }

  reservePrompt(requestId) {
    this.assertIdle();
    if (this.activeRequestId) throw new GarpError(GarpErrorCode.SESSION_BUSY, "Prompt reservation already exists");
    this.activeRequestId = requestId;
    this.lastRequestId = requestId;
    this.transition("BUSY");
  }

  clearActivePrompt() {
    this.activeRequestId = null;
    this.generationState = "IDLE";
    if (this.state === "BUSY" || this.state === "RECOVERING" || this.state === "RETRYING") this.state = "READY";
  }

  incrementPageGeneration(url = "") {
    if (this.pageGeneration >= GARP_UINT64_MAX) throw new GarpError(GarpErrorCode.PAGE_GENERATION_OVERFLOW, "Page generation exceeded uint64");
    this.pageGeneration += 1n;
    if (url) this.pageURL = url;
    this.actorInstance = null;
    this.actorObject = null;
    return this.pageGeneration;
  }

  markPageGeneration(value, url = "") {
    const next = uint64(String(value), "page_generation");
    if (next > this.pageGeneration) this.pageGeneration = next;
    if (url) this.pageURL = url;
  }

  commitEvent(envelope) {
    if (this.eventSequence >= GARP_UINT64_MAX) throw new GarpError(GarpErrorCode.EVENT_SEQUENCE_OVERFLOW, "Session event sequence overflow");
    if (this.eventHistory.length >= GARP_MAX_QUEUED_EVENTS) throw new GarpError(GarpErrorCode.EVENT_QUEUE_OVERFLOW, "Session event queue limit exceeded");
    this.eventSequence += 1n;
    const committed = structuredClone({ ...envelope, sequence: String(this.eventSequence) });
    const size = byteLength(JSON.stringify(committed));
    const maxBytes = GARP_MAX_EVENT_HISTORY_MEMORY_MB * 1024 * 1024;
    if (size > maxBytes) throw new GarpError(GarpErrorCode.EVENT_QUEUE_OVERFLOW, "Single event exceeds event history memory budget");
    while (this.eventHistoryBytes + size > maxBytes && this.eventHistory.length) {
      const removed = this.eventHistory.shift();
      this.eventHistoryBytes -= byteLength(JSON.stringify(removed));
    }
    this.eventHistory.push(committed);
    this.eventHistoryBytes += size;
    return committed;
  }

  oldestSequence() { return this.eventHistory.length ? BigInt(this.eventHistory[0].sequence) : this.eventSequence + 1n; }
  lastSequence() { return this.eventSequence; }

  snapshot() {
    return {
      session_id: this.sessionId,
      provider: this.provider,
      model: this.model,
      tab_id: this.tabId,
      url: this.pageURL || "",
      page_generation: String(this.pageGeneration),
      active_prompt_request_id: this.activeRequestId,
      state: this.state,
      input_state: this.inputState,
      generation_state: this.generationState,
      last_request_id: this.lastRequestId,
      last_message_id: this.lastMessageId,
      last_message_count: this.lastMessageCount,
      event_sequence: String(this.eventSequence),
    };
  }
}
