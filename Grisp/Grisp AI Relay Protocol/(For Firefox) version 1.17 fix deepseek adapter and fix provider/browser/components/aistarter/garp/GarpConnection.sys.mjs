import { garpDebug, garpError } from "../GarpDebug.sys.mjs";
import { encodeGarpEnvelope, decodeGarpFrame, peekHeader } from "./GarpFrame.sys.mjs";
import { GARP_HANDSHAKE_LIMIT, GARP_HANDSHAKE_TIMEOUT_MS, GARP_MAX_OUTSTANDING_REQUESTS } from "./GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";
import { createRepeatingTimer, monotonicNow } from "./GarpUtil.sys.mjs";
const COMMANDS = new Set(["HELLO", "HELLO_AUTH", "LIST_TABS", "OPEN_TAB", "CLOSE_TAB", "SELECT_TAB", "GET_CAPABILITIES", "CREATE_SESSION", "ATTACH_SESSION", "DETACH_SESSION", "CLOSE_SESSION", "RESET_SESSION", "GET_SESSION", "PROMPT", "CANCEL_PROMPT", "GET_PROMPT_STATUS", "GET_RESPONSE", "SUBSCRIBE_RESPONSE", "CONTINUE_PROMPT", "GET_EVENTS", "PING"]);

export class GarpConnection {
    constructor(transport, service) {
        this.transport = transport;
        this.service = service;
        this.outStream = transport.openOutputStream(0, 0, 0);
        this.inStream = transport.openInputStream(0, 0, 0);
        this.buffer = new Uint8Array(0);
        this.closed = false;
        this.authenticated = false;
        this.authState = "NEW";
        this.peerCapabilitiesValidated = false;
        this.peerCapabilities = null;
        this.clientName = null;
        this.clientVersion = null;
        this.clientNonce = null;
        this.serverNonce = null;
        this.offeredFeatures = [];
        this.negotiatedFeatures = [];
        this.handshakeRequestId = null;
        this.outstanding = new Map();
        this.completedResponses = new Map();
        this.seenRequestIds = new Map();
        this.lastOutboundProtocolTime = monotonicNow();
        this.lastInboundAuthenticatedTime = monotonicNow();
        this.handshakeDeadline = monotonicNow() + GARP_HANDSHAKE_TIMEOUT_MS;
        this.dispatchQueue = Promise.resolve();
        this.pump = Cc["@mozilla.org/network/input-stream-pump;1"].createInstance(Ci.nsIInputStreamPump);
        this.pump.init(this.inStream, 0, 0, false);
        this.pump.asyncRead(this);
        this.timer = createRepeatingTimer(() => this.tick(), 250);
    }
    currentInboundLimit() {
        return this.peerCapabilitiesValidated ? Math.min(this.peerCapabilities?.limits?.max_payload_bytes ?? GARP_HANDSHAKE_LIMIT, 0xffffffff) : GARP_HANDSHAKE_LIMIT;
    }
    tick() {
        if (this.closed)
            return;
        const now = monotonicNow();
        if (!this.authenticated && now >= this.handshakeDeadline) {
            this.fail(new GarpError(GarpErrorCode.HANDSHAKE_TIMEOUT, "GARP handshake timeout"));
            return;
        }
        for (const [id, e] of this.completedResponses) {
            if (now - e.committedAt > Number(this.service.capabilities.limits.response_retention_ms))
                this.completedResponses.delete(id);
        }
        if (this.authenticated && this.negotiatedFeatures.includes("ext-pong")) {
            const k = this.service.capabilities.keepalive;
            if (k.enabled && now - this.lastOutboundProtocolTime >= Number(k.interval_ms))
                this.send("PONG", {}, { request_id: null, session_id: null, sequence: null });
            if (now - this.lastInboundAuthenticatedTime >= Number(k.idle_timeout_ms))
                this.close();
        }
    }
    currentInboundLimitForFrame() {
        return this.currentInboundLimit();
    }
    onStartRequest() { }
    onDataAvailable(_request, stream, _offset, count) {
        if (this.closed)
            return;
        garpDebug(2, "socket data received", {
            bytes: count,
            buffered_before: this.buffer.length,
            authenticated: !!this.authenticated,
        });
        const b = Cc["@mozilla.org/binaryinputstream;1"].createInstance(Ci.nsIBinaryInputStream);
        b.setInputStream(stream);
        const bytes = new Uint8Array(b.readByteArray(count));
        this.buffer = this.merge(this.buffer, bytes);
        this.processFrames();
    }
    merge(a, b) {
        const c = new Uint8Array(a.length + b.length);
        c.set(a);
        c.set(b, a.length);
        return c;
    }
    onStopRequest() {
        this.close();
    }
    processFrames() {
        while (!this.closed) {
            if (this.buffer.length < 48)
                return;
            const h = peekHeader(this.buffer);
            if (!h)
                return;
            if (this.buffer[0] !== 71 || this.buffer[1] !== 65 || this.buffer[2] !== 82 || this.buffer[3] !== 80) {
                this.fail(new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Invalid GARP magic"));
                return;
            }
            if (h.wireVersion !== 0) {
                this.fail(new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, "Unsupported wire version"));
                return;
            }
            if (h.headerLength !== 48) {
                this.fail(new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Header length must be 48"));
                return;
            }
            const limit = this.currentInboundLimitForFrame(h);
            if (h.payloadLength > limit) {
                this.fail(new GarpError(GarpErrorCode.FRAME_TOO_LARGE, "Frame payload exceeds receive limit"));
                return;
            }
            const length = 48 + h.payloadLength;
            if (this.buffer.length < length)
                return;
            const frame = this.buffer.slice(0, length);
            this.buffer = this.buffer.slice(length);
            let decoded;
            try {
                decoded = decodeGarpFrame(frame);
            }
            catch (e) {
                garpError("frame decode failed", {
                    error: e?.message || String(e),
                    bytes: frame.length,
                });
                this.fail(e);
                return;
            }
            garpDebug(1, "frame decoded", {
                type: decoded.type,
                request_id: decoded.request_id ?? null,
                session_id: decoded.session_id ?? null,
                payload_bytes: h.payloadLength,
                authenticated: !!this.authenticated,
            });
            this.dispatchQueue = this.dispatchQueue.then(() => this.dispatchDecoded(decoded)).catch(e => this.handleDispatchError(e, decoded));
        }
    }
    dispatchDecoded(decoded) {
        const type = decoded.type;
        garpDebug(2, "dispatch decoded frame", {
            type,
            request_id: decoded.request_id ?? null,
            session_id: decoded.session_id ?? null,
            auth_state: this.authState,
            authenticated: !!this.authenticated,
        });
        if (type === "CAPABILITIES") {
            if (!this.authenticated)
                throw new GarpError(GarpErrorCode.AUTH_REQUIRED, "Authentication required");
            this.service.handleGarpMessage(this, decoded);
            return undefined;
        }
        if (type === "PONG") {
            if (!this.authenticated)
                throw new GarpError(GarpErrorCode.AUTH_REQUIRED, "Authentication required");
            this.lastInboundAuthenticatedTime = monotonicNow();
            return undefined;
        }
        if (this.authenticated)
            this.lastInboundAuthenticatedTime = monotonicNow();
        if (type === "HELLO") {
            this.admitRequest(decoded.request_id, type, decoded.message);
            return this.service.handleGarpMessage(this, decoded);
        }
        if (type === "HELLO_AUTH") {
            if (decoded.request_id !== this.handshakeRequestId || !this.outstanding.has(decoded.request_id))
                throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "HELLO_AUTH does not match HELLO");
            return this.service.handleGarpMessage(this, decoded);
        }
        if (COMMANDS.has(type)) {
            if (!this.authenticated)
                throw new GarpError(GarpErrorCode.AUTH_REQUIRED, "Authentication required");
            if (!this.admitRequest(decoded.request_id, type, decoded.message))
                return undefined;
        }
        return this.service.handleGarpMessage(this, decoded);
    }
    semanticFingerprint(message) {
        const c = structuredClone(message);
        delete c.timestamp;
        return JSON.stringify(c);
    }
    admitRequest(id, type, message) {
        if (!id)
            throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Command request_id must be non-nil");
        const prior = this.completedResponses.get(id), seen = this.seenRequestIds.get(id);
        if (this.outstanding.has(id) || prior || seen) {
            if (prior && prior.fingerprint === this.semanticFingerprint(message)) {
                this.sendEnvelope(prior.envelope, false);
                return false;
            }
            throw new GarpError(GarpErrorCode.DUPLICATE_REQUEST, "Duplicate request_id");
        }
        if (this.outstanding.size >= GARP_MAX_OUTSTANDING_REQUESTS)
            throw new GarpError(GarpErrorCode.OUTSTANDING_REQUEST_LIMIT, "Maximum outstanding requests reached");
        const fingerprint = this.semanticFingerprint(message);
        this.seenRequestIds.set(id, { type, fingerprint, seenAt: monotonicNow() });
        this.outstanding.set(id, { type, fingerprint, acceptedAt: monotonicNow() });
        return true;
    }
    commitRequestResponse(id, envelope) {
        if (!id)
            return;
        const p = this.outstanding.get(id), s = this.seenRequestIds.get(id);
        this.outstanding.delete(id);
        this.completedResponses.set(id, { fingerprint: p?.fingerprint || s?.fingerprint || null, envelope: structuredClone(envelope), committedAt: monotonicNow() });
    }
    send(type, payload = {}, options = {}) {
        if (this.closed)
            return false;
        const envelope = { garp: "1.24", type: typeof type === "number" ? String(type) : String(type).toUpperCase(), request_id: options.request_id ?? null, session_id: options.session_id ?? null, timestamp: options.timestamp || new Date().toISOString(), sequence: options.sequence ?? null, payload };
        garpDebug(1, "frame send", {
            type: envelope.type,
            request_id: envelope.request_id,
            session_id: envelope.session_id,
            payload_keys: payload && typeof payload === "object" ? Object.keys(payload) : [],
            command_response: options.isCommandResponse === true,
        });
        try {
            return this.sendEnvelope(envelope, options.isCommandResponse === true);
        }
        catch (e) {
            this.fail(e);
            return false;
        }
    }
    sendEnvelope(envelope, isCommandResponse = false) {
        if (this.closed)
            return false;
        const limit = this.peerCapabilitiesValidated ? Math.min(this.peerCapabilities?.limits?.max_payload_bytes ?? GARP_HANDSHAKE_LIMIT, 0xffffffff) : GARP_HANDSHAKE_LIMIT;
        const frame = encodeGarpEnvelope(envelope, { enforceMaxPayload: limit });
        if (isCommandResponse && envelope.request_id)
            this.commitRequestResponse(envelope.request_id, envelope);
        const out = Cc["@mozilla.org/binaryoutputstream;1"].createInstance(Ci.nsIBinaryOutputStream);
        out.setOutputStream(this.outStream);
        out.writeByteArray(frame, frame.length);
        this.lastOutboundProtocolTime = monotonicNow();
        return true;
    }
    setPeerCapabilities(payload) {
        this.peerCapabilities = structuredClone(payload);
        this.peerCapabilitiesValidated = true;
    }
    sendResponse(id, sid, payload) {
        return this.send("RESPONSE", payload, { request_id: id, session_id: sid, sequence: null, isCommandResponse: true });
    }
    sendError(error, requestId = null, sessionId = null, commandCorrelated = false) {
        const payload = { code: error?.code || GarpErrorCode.PROVIDER_ERROR, message: error?.message || String(error) };
        if (error?.details)
            payload.details = error.details;
        return this.send("ERROR", payload, { request_id: commandCorrelated ? requestId : null, session_id: commandCorrelated ? sessionId : null, sequence: null, isCommandResponse: commandCorrelated });
    }
    handleDispatchError(error, decoded) {
        this.lastError = error;
        garpError("GARP dispatch error", {
            type: decoded?.type || null,
            request_id: decoded?.request_id || null,
            session_id: decoded?.session_id || null,
            code: error?.code || null,
            message: error?.message || String(error),
        });
        const correlated = !!decoded?.request_id && this.outstanding.has(decoded.request_id);
        this.sendError(error, correlated ? decoded.request_id : null, correlated ? decoded.session_id : null, correlated);
        if (!this.authenticated || [GarpErrorCode.UNSUPPORTED_WIRE_VERSION, GarpErrorCode.PROTOCOL_ERROR].includes(error?.code))
            this.close();
    }
    fail(error) {
        try {
            this.sendError(error, null, null, false);
        }
        catch (_) { }
        this.close();
    }
    close() {
        if (this.closed)
            return;
        garpDebug(1, "connection closing", {
            authenticated: !!this.authenticated,
            auth_state: this.authState,
            outstanding: this.outstanding?.size ?? 0,
            last_error: this.lastError?.message || null,
        });
        this.closed = true;
        if (this.timer) {
            try {
                this.timer.cancel();
            }
            catch (_) { }
            this.timer = null;
        }
        try {
            this.pump.cancel(0x804B0002);
        }
        catch (_) { }
        try {
            this.inStream.close();
        }
        catch (_) { }
        try {
            this.outStream.close();
        }
        catch (_) { }
        this.service.removeConnection(this);
    }
}

