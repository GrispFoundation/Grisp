import { GARP_UINT64_MAX } from "../garp/GarpRegistry.sys.mjs";

import { GarpError, GarpErrorCode } from "../garp/GarpErrors.sys.mjs";

export const PromptState = Object.freeze({ PENDING: "PENDING", SUBMITTING: "SUBMITTING", GENERATING: "GENERATING", WAITING_CONTINUATION: "WAITING_CONTINUATION", CANCELLING: "CANCELLING", COMPLETED: "COMPLETED", FAILED: "FAILED", CANCELLED: "CANCELLED" });

export class GarpMessageState {
    constructor(messageId) {
        this.messageId = messageId;
        this.revision = 0n;
        this.content = "";
        this.lastObservedText = "";
        this.hasCommittedContent = false;
        this.started = false;
    }

    apply(observed) {
        const text = String(observed ?? "");
        if (text === this.content)
            return null;
        let mode = "REPLACE", delta = text;
        if (text.startsWith(this.content)) {
            mode = "APPEND";
            delta = text.slice(this.content.length);
        }
        const next = this.revision + 1n;
        if (next > GARP_UINT64_MAX)
            throw new GarpError(GarpErrorCode.REVISION_GAP, "Message revision overflow");
        this.revision = next;
        this.content = text;
        this.lastObservedText = text;
        if (text.length > 0)
            this.hasCommittedContent = true;
        return { revision: String(next), delta, mode };
    }
}

export class GarpRequest {
    constructor(requestId, sessionId, prompt, options = {}) {
        this.requestId = requestId;
        this.sessionId = sessionId;
        this.prompt = prompt;
        this.options = Object.freeze({ ...options });
        this.state = PromptState.PENDING;
        this.messages = new Map();
        this.messageOrder = [];
        this.lastMessageCount = 0;
        this.baselineMessageCount = 0;
        this.baselineMessageText = "";
        this.lastPageGeneration = 1n;
        this.actorInstance = null;
        this.provider = null;
        this.continuationCount = 0;
        this.maxContinuations = Number(options.max_continuations ?? 8);
        this.promptDeadline = null;
        this.continuationWaitDeadline = null;
        this.startedAt = globalThis.performance?.now?.() ?? Date.now();
        this.completedAt = null;
        this.responseStarted = false;
        this.partial = false;
        this.terminalCommitted = false;
        this.error = null;
        this.cancelAccepted = false;
        this.cancellationVerified = false;
        this.providerOperationEpoch = 0;
        this.continuationEpoch = 0;
        this.timeoutEpoch = 0;
        this.cancelEpoch = 0;
        this.fencingEpoch = 0;
    }

    get terminal() {
        return [PromptState.COMPLETED, PromptState.FAILED, PromptState.CANCELLED].includes(this.state);
    }

    get contentCommitted() {
        if (this.partial)
            return true;
        for (const m of this.messages.values())
            if (m.hasCommittedContent)
                return true;
        return false;
    }

    ensureMessage(id) {
        let m = this.messages.get(id);
        if (!m) {
            m = new GarpMessageState(id);
            this.messages.set(id, m);
            this.messageOrder.push(id);
        }
        return m;
    }

    aggregateContent() {
        if (this.messageOrder.length === 0)
            return "";
        if (this.messageOrder.length === 1)
            return this.messages.get(this.messageOrder[0]).content;
        return this.messages.get(this.messageOrder[this.messageOrder.length - 1]).content;
    }

    snapshot() {
        const first = this.messageOrder.length ? this.messages.get(this.messageOrder[0]) : null;
        return { success: true, prompt_request_id: this.requestId, state: this.state, page_generation: String(this.lastPageGeneration), message_id: first?.messageId ?? null, revision: first ? String(first.revision) : "0", continuation_count: this.continuationCount, max_continuations: this.maxContinuations, partial: this.partial, ...(this.error ? { error: this.error } : {}) };
    }
}
