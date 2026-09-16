import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

const NIL = "00000000-0000-0000-0000-000000000000";

export class AIAutomationSession {
  constructor({ sessionId, provider, tabId, pageGeneration = 1 }) {
    this.sessionId = sessionId;
    this.provider = provider;
    this.model = null;
    this.tabId = tabId;
    this.pageGeneration = BigInt(pageGeneration);
    this.state = "CREATED";                 // §29
    this.inputState = "UNKNOWN";
    this.activeRequestId = null;
    this.lastRequestId = null;
    this.lastMessageId = null;
    this.lastMessageText = "";
    this.lastMessageCount = 0;
    this.pageURL = "";
    this.subscribers = new Set();           // connections receiving events for this session
    this._sequence = 0n;                     // §86: first event is 1
    this._lastActor = null;
    this.actorInstance = crypto.randomUUID(); // §92
  }

  nextSequence() {
    this._sequence += 1n;
    if (this._sequence > 0xFFFFFFFFFFFFFFFFn) {
      // §86 fail-closed.
      throw new GarpError(GarpErrorCode.EVENT_SEQUENCE_OVERFLOW, "event sequence overflow");
    }
    return this._sequence;
  }

  attachToConnection(connection) { this.subscribers.add(connection); }
  detachFromConnection(connection) { this.subscribers.delete(connection); }

  assertIdle() {
    if (this.activeRequestId) {
      throw new GarpError(GarpErrorCode.SESSION_BUSY, "session has an active prompt", {
        provider: this.provider,
        state: "BUSY",
      });
    }
  }

  incrementPageGeneration(url) {
    this.pageGeneration += 1n;
    if (this.pageGeneration > 0xFFFFFFFFFFFFFFFFn) {
      throw new GarpError(GarpErrorCode.PAGE_GENERATION_OVERFLOW, "page generation overflow");
    }
    this.actorInstance = crypto.randomUUID();
    if (url) this.pageURL = url;
  }

  reset() {
    // §32: preserve session_id and event sequence; increment page generation.
    this.assertIdle();
    this.state = "PREPARING";
    this.lastRequestId = null;
    this.lastMessageId = null;
    this.lastMessageText = "";
    this.lastMessageCount = 0;
    this.incrementPageGeneration(this.pageURL);
  }

  snapshot() {
    return {
      session_id: this.sessionId,
      provider: this.provider,
      model: this.model,
      tab_id: this.tabId,
      page_generation: String(this.pageGeneration),
      input_state: this.inputState,
      state: this.state,
      active_prompt_request_id: this.activeRequestId,
      url: this.pageURL,
    };
  }
}