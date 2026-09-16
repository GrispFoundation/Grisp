import { encodeGarpEnvelope, decodeGarpFrame, peekHeader } from "./GarpFrame.sys.mjs";
import {
  GARP_HANDSHAKE_LIMIT,
  GARP_HANDSHAKE_TIMEOUT_MS,
  GARP_MAX_OUTSTANDING_REQUESTS,
  messageTypeName,
} from "./GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";
import { encodeTranscriptCore, monotonicNow, sha256 } from "./GarpUtil.sys.mjs";

const COMMAND_TYPES = new Set([
  "HELLO", "HELLO_AUTH", "LIST_TABS", "OPEN_TAB", "CLOSE_TAB", "SELECT_TAB", "GET_CAPABILITIES", "CREATE_SESSION", "ATTACH_SESSION", "DETACH_SESSION", "CLOSE_SESSION", "RESET_SESSION", "GET_SESSION", "PROMPT", "CANCEL_PROMPT", "GET_PROMPT_STATUS", "GET_RESPONSE", "SUBSCRIBE_RESPONSE", "CONTINUE_PROMPT", "GET_EVENTS", "PING",
]);

function mergeBytes(left, right) {
  const output = new Uint8Array(left.length + right.length);
  output.set(left, 0); output.set(right, left.length); return output;
}

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
    this.lastOutboundProtocolTime = monotonicNow();
    this.lastInboundAuthenticatedTime = monotonicNow();
    this.dispatchQueue = Promise.resolve();
    this.outstanding = new Map();
    this.completedResponses = new Map();
    this.seenRequestIds = new Map();
    this.negotiatedFeatures = [];
    this.handshakeDeadline = monotonicNow() + GARP_HANDSHAKE_TIMEOUT_MS;
    this.lastError = null;

    this.pump = Cc["@mozilla.org/network/input-stream-pump;1"].createInstance(Ci.nsIInputStreamPump);
    this.pump.init(this.inStream, 0, 0, false);
    this.pump.asyncRead(this);

    this.timer = setInterval(() => this.tick(), 250);
  }

  currentInboundLimit() { return this.peerCapabilitiesValidated ? Math.min(this.peerCapabilities?.limits?.max_payload_bytes ?? GARP_HANDSHAKE_LIMIT, 0xffffffff) : GARP_HANDSHAKE_LIMIT; }

  async replayKey() {
    const core = encodeTranscriptCore(
      this.clientNonce,
      this.serverNonce,
      "1.24",
      "0x00",
      this.offeredFeatures,
      this.negotiatedFeatures,
      this.clientName,
      this.clientVersion,
      this.service.serverName,
      this.service.serverVersion
    );
    const digest = await sha256(core);
    return [...digest].map(byte => byte.toString(16).padStart(2, "0")).join("");
  }


  tick() {
    if (this.closed) return;
    const now = monotonicNow();
    if (!this.authenticated && now >= this.handshakeDeadline) {
      this.sendError(new GarpError(GarpErrorCode.HANDSHAKE_TIMEOUT, "GARP handshake timeout"), null, null, false);
      this.close(); return;
    }
    for (const [id, entry] of this.completedResponses) { if (monotonicNow() - entry.committedAt > Number(this.service.capabilities.limits.response_retention_ms)) this.completedResponses.delete(id); }
    if (this.authenticated && this.negotiatedFeatures.includes("ext-pong")) {
      const keep = this.service.capabilities.keepalive;
      if (keep.enabled && now - this.lastOutboundProtocolTime >= Number(keep.interval_ms)) {
        this.send("PONG", {}, { request_id: null, session_id: null, sequence: null, maxPayloadBytes: this.currentInboundLimit() });
      }
      if (now - this.lastInboundAuthenticatedTime >= Number(keep.idle_timeout_ms)) {
        this.close();
      }
    }
  }

  onStartRequest() {}

  onDataAvailable(_request, stream, _offset, count) {
    if (this.closed) return;
    const binaryStream = Cc["@mozilla.org/binaryinputstream;1"].createInstance(Ci.nsIBinaryInputStream);
    binaryStream.setInputStream(stream);
    const bytes = new Uint8Array(binaryStream.readByteArray(count));
    if (this.buffer.length + bytes.length > this.currentInboundLimit() + 48 + 65536) {
      this.fail(new GarpError(GarpErrorCode.FRAME_TOO_LARGE, "Inbound buffering limit exceeded")); return;
    }
    this.buffer = mergeBytes(this.buffer, bytes);
    this.processFrames();
  }

  onStopRequest(_request, _status) { this.close(); }

  processFrames() {
    while (!this.closed) {
      if (this.buffer.length < 48) return;
      const header = peekHeader(this.buffer);
      if (this.buffer[0] !== 0x47 || this.buffer[1] !== 0x41 || this.buffer[2] !== 0x52 || this.buffer[3] !== 0x50) { this.fail(new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Invalid GARP magic")); return; }
      if (header.wireVersion !== 0) { this.fail(new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, "Unsupported wire version")); return; }
      if (header.headerLength !== 48) { this.fail(new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Header length must be 48")); return; }
      const limit = this.currentInboundLimit();
      if (header.payloadLength > limit) { this.fail(new GarpError(GarpErrorCode.FRAME_TOO_LARGE, `Frame payload exceeds ${limit} byte receive limit`)); return; }
      const frameLength = 48 + header.payloadLength;
      if (this.buffer.length < frameLength) return;
      const frame = this.buffer.slice(0, frameLength);
      this.buffer = this.buffer.slice(frameLength);
      let decoded;
      try { decoded = decodeGarpFrame(frame); } catch (error) { this.fail(error); return; }
      this.dispatchQueue = this.dispatchQueue.then(() => this.dispatchDecoded(decoded)).catch(error => this.handleDispatchError(error, decoded));
    }
  }

  async dispatchDecoded(decoded) {
    const message = decoded.message;
    const type = decoded.type;
    const isCommand = COMMAND_TYPES.has(type);

    if (this.authenticated && !this.peerCapabilitiesValidated && type !== "CAPABILITIES" && decoded.payloadLength > GARP_HANDSHAKE_LIMIT) throw new GarpError(GarpErrorCode.FRAME_TOO_LARGE, "Handshake receive limit exceeded");

    if (this.authenticated) this.lastInboundAuthenticatedTime = monotonicNow();

    if (isCommand) {
      if (type === "HELLO_AUTH") {
        // Handshake transaction is one request-ID entry.
        if (!this.outstanding.has(decoded.request_id)) {
          // HELLO is parsed first and owns the entry.
          throw new GarpError(GarpErrorCode.INVALID_MESSAGE_STATE, "HELLO_AUTH does not match active handshake transaction");
        }
      } else if (type === "HELLO") {
        this.admitRequest(decoded.request_id, type, message);
      } else if (type !== "CAPABILITIES" && type !== "PONG" && !this.authenticated) {
        throw new GarpError(GarpErrorCode.AUTH_REQUIRED, "Authentication required");
      } else if (type !== "CAPABILITIES" && type !== "PONG") {
        if (!this.admitRequest(decoded.request_id, type, message)) return;
      }
    }

    await this.service.handleGarpMessage(this, decoded);
  }

  semanticFingerprint(message) {
    const clone = JSON.parse(JSON.stringify(message));
    if (clone.timestamp !== undefined) delete clone.timestamp;
    return JSON.stringify(clone);
  }

  admitRequest(requestId, type, message) {
    if (!requestId) throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Command request_id must be non-nil");
    const prior = this.completedResponses.get(requestId);
    const seen = this.seenRequestIds.get(requestId);
    if (this.outstanding.has(requestId) || prior || seen) {
      if (prior && prior.fingerprint === this.semanticFingerprint(message)) {
        this.sendEnvelope(prior.envelope, false);
        return false;
      }
      throw new GarpError(GarpErrorCode.DUPLICATE_REQUEST, "Duplicate request_id");
    }
    if (this.outstanding.size >= GARP_MAX_OUTSTANDING_REQUESTS) throw new GarpError(GarpErrorCode.OUTSTANDING_REQUEST_LIMIT, "Maximum outstanding requests reached");
    const fingerprint = this.semanticFingerprint(message);
    this.seenRequestIds.set(requestId, { type, fingerprint, seenAt: monotonicNow() });
    this.outstanding.set(requestId, { type, fingerprint, acceptedAt: monotonicNow() });
    return true;
  }

  commitRequestResponse(requestId, envelope) {
    if (!requestId) return;
    const pending = this.outstanding.get(requestId);
    const seen = this.seenRequestIds.get(requestId);
    const fingerprint = pending?.fingerprint || seen?.fingerprint || null;
    this.outstanding.delete(requestId);
    this.completedResponses.set(requestId, {
      fingerprint,
      envelope: structuredClone(envelope),
      committedAt: monotonicNow(),
    });
  }

  send(type, payload = {}, options = {}) {
    if (this.closed) return false;
    const requestId = options.request_id ?? null;
    const sessionId = options.session_id ?? null;
    const sequence = options.sequence ?? null;
    const envelope = {
      garp: "1.24",
      type: typeof type === "number" ? messageTypeName(type) : String(type).toUpperCase(),
      request_id: requestId,
      session_id: sessionId,
      timestamp: options.timestamp || new Date().toISOString(),
      sequence,
      payload,
    };
    try {
      return this.sendEnvelope(envelope, options.isCommandResponse === true);
    } catch (error) {
      this.fail(error);
      return false;
    }
  }

  sendEnvelope(envelope, isCommandResponse = false) {
    if (this.closed) return false;
    const outboundLimit = this.peerCapabilitiesValidated ? Math.min(this.peerCapabilities?.limits?.max_payload_bytes ?? GARP_HANDSHAKE_LIMIT, 0xffffffff) : GARP_HANDSHAKE_LIMIT;
    const frame = encodeGarpEnvelope(envelope, { enforceMaxPayload: outboundLimit });
    if (isCommandResponse && envelope.request_id) {
      this.commitRequestResponse(envelope.request_id, envelope);
    }
    const output = Cc["@mozilla.org/binaryoutputstream;1"].createInstance(Ci.nsIBinaryOutputStream);
    output.setOutputStream(this.outStream);
    output.writeByteArray(frame, frame.length);
    this.lastOutboundProtocolTime = monotonicNow();
    return true;
  }

  setPeerCapabilities(payload) { this.peerCapabilities = payload; this.peerCapabilitiesValidated = true; }

  sendResponse(requestId, sessionId, payload) {
    return this.send("RESPONSE", payload, { request_id: requestId, session_id: sessionId, sequence: null, isCommandResponse: true });
  }

  sendError(error, requestId = null, sessionId = null, commandCorrelated = false) {
    const payload = { code: error?.code || GarpErrorCode.PROVIDER_ERROR, message: error?.message || String(error) };
    if (error?.details) payload.details = error.details;
    return this.send("ERROR", payload, { request_id: requestId, session_id: sessionId, sequence: null, isCommandResponse: commandCorrelated });
  }

  handleDispatchError(error, decoded) {
    this.lastError = error;
    const requestId = decoded?.request_id || null;
    const sessionId = decoded?.session_id || null;
    const commandCorrelated = !!requestId && this.outstanding.has(requestId);
    this.sendError(error, commandCorrelated ? requestId : null, commandCorrelated ? sessionId : null, commandCorrelated);
    if (!this.authenticated || [GarpErrorCode.UNSUPPORTED_WIRE_VERSION, GarpErrorCode.PROTOCOL_ERROR].includes(error?.code)) this.close();
  }

  fail(error) {
    this.sendError(error, null, null, false);
    this.close();
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    try { clearInterval(this.timer); } catch (_) {}
    try { this.pump.cancel(0x804B0002); } catch (_) {}
    try { this.inStream.close(); } catch (_) {}
    try { this.outStream.close(); } catch (_) {}
    this.service.removeConnection(this);
  }
}
