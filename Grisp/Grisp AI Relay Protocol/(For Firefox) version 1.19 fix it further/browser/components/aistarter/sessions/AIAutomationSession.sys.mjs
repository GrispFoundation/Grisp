import { GARP_MAX_EVENT_HISTORY_MEMORY_MB, GARP_MAX_QUEUED_EVENTS, GARP_UINT64_MAX, } from "../garp/GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";
import { byteLength, uuid } from "../garp/GarpUtil.sys.mjs";
import { garpDebug } from "../GarpDebug.sys.mjs";
const TRANS = { CREATED: ["PREPARING", "FAILED", "CLOSED"], PREPARING: ["READY", "AUTH_REQUIRED", "RATE_LIMITED", "RETRYING", "RECOVERING", "FAILED", "CLOSED"], READY: ["BUSY", "PREPARING", "AUTH_REQUIRED", "RATE_LIMITED", "RECOVERING", "FAILED", "CLOSED"], BUSY: ["READY", "PREPARING", "RETRYING", "AUTH_REQUIRED", "RATE_LIMITED", "RECOVERING", "FAILED", "CLOSED"], AUTH_REQUIRED: ["PREPARING", "FAILED", "CLOSED"], RATE_LIMITED: ["PREPARING", "FAILED", "CLOSED"], RECOVERING: ["READY", "BUSY", "RETRYING", "FAILED", "CLOSED"], RETRYING: ["BUSY", "PREPARING", "FAILED", "CLOSED"], FAILED: ["PREPARING", "CLOSED"], CLOSED: [] };
export class AIAutomationSession {
    constructor({ sessionId, provider, tabId, pageGeneration = 1n }) {
        this.sessionId = sessionId || uuid();
        this.provider = provider;
        this.authoritativeProvider = provider;
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
        this.actorObject = null;
        this.actorInstance = null;
        this.childActorInstance = null;
        this.ownerConnection = null;
        this.eventSequence = 0n;
        this.eventHistory = [];
        this.eventHistoryBytes = 0;
        this.subscribers = new Set();
        this.arbiterTail = Promise.resolve();
    }
    enqueue(_label, op) {
        const run = this.arbiterTail.then(() => op());
        this.arbiterTail = run.catch(() => { });
        return run;
    }
    transition(s) {
        if (s === this.state)
            return;
        if (!TRANS[this.state]?.includes(s))
            throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, `Invalid session transition ${this.state} -> ${s}`);
        garpDebug(1, "session state transition", {
            session_id: this.sessionId,
            provider: this.provider,
            from: this.state,
            to: s,
            page_generation: String(this.pageGeneration),
            active_request_id: this.activeRequestId,
        });
        this.state = s;
    }
    assertMutable() {
        if (this.state === "CLOSED")
            throw new GarpError(GarpErrorCode.SESSION_CLOSED, "Session is closed");
    }
    assertIdle() {
        this.assertMutable();
        if (this.activeRequestId)
            throw new GarpError(GarpErrorCode.SESSION_BUSY, "Session already has an active prompt");
        if (this.state !== "READY")
            throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, `Session is not READY: ${this.state}`);
    }
    reservePrompt(id) {
        this.assertIdle();
        this.activeRequestId = id;
        this.lastRequestId = id;
        this.transition("BUSY");
        garpDebug(1, "session prompt reserved", {
            session_id: this.sessionId,
            request_id: id,
            provider: this.provider,
        });
    }
    clearActivePrompt() {
        this.activeRequestId = null;
        this.generationState = "IDLE";
        if (this.state === "BUSY" || this.state === "RECOVERING" || this.state === "RETRYING")
            this.state = "READY";
    }
    incrementPageGeneration(url = "") {
        if (this.pageGeneration >= GARP_UINT64_MAX)
            throw new GarpError(GarpErrorCode.PAGE_GENERATION_OVERFLOW, "Page generation overflow");
        this.pageGeneration++;
        if (url)
            this.pageURL = url;
        this.actorObject = null;
        this.actorInstance = null;
        this.childActorInstance = null;
        return this.pageGeneration;
    }
    commitEvent(envelope) {
        if (this.eventSequence >= GARP_UINT64_MAX)
            throw new GarpError(GarpErrorCode.EVENT_SEQUENCE_OVERFLOW, "Event sequence overflow");
        this.eventSequence++;
        const committed = structuredClone({ ...envelope, sequence: String(this.eventSequence) });
        const size = byteLength(JSON.stringify(committed)), max = GARP_MAX_EVENT_HISTORY_MEMORY_MB * 1024 * 1024;
        if (size > max)
            throw new GarpError(GarpErrorCode.EVENT_QUEUE_OVERFLOW, "Event exceeds history memory budget");
        while (this.eventHistory.length >= GARP_MAX_QUEUED_EVENTS || this.eventHistoryBytes + size > max) {
            if (!this.eventHistory.length)
                throw new GarpError(GarpErrorCode.EVENT_QUEUE_OVERFLOW, "Event queue overflow");
            this.eventHistoryBytes -= byteLength(JSON.stringify(this.eventHistory.shift()));
        }
        this.eventHistory.push(committed);
        this.eventHistoryBytes += size;
        garpDebug(2, "session event committed", {
            session_id: this.sessionId,
            type: committed.type,
            sequence: committed.sequence,
            event_history_count: this.eventHistory.length,
        });
        return committed;
    }
    oldestSequence() {
        return this.eventHistory.length ? BigInt(this.eventHistory[0].sequence) : this.eventSequence + 1n;
    }
    lastSequence() {
        return this.eventSequence;
    }
    snapshot() {
        return { session_id: this.sessionId, provider: this.provider, tab_id: this.tabId, url: this.pageURL, page_generation: String(this.pageGeneration), state: this.state, input_state: this.inputState, generation_state: this.generationState, active_prompt_request_id: this.activeRequestId, last_request_id: this.lastRequestId, last_message_id: this.lastMessageId, last_message_count: this.lastMessageCount, event_sequence: String(this.eventSequence) };
    }
}

