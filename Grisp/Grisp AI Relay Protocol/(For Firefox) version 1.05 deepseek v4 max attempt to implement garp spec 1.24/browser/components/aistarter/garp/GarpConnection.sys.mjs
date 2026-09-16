import { encodeEnvelope, encodeFrame, decodeFrame } from "./GarpFrame.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";
import { GARP_HANDSHAKE_LIMIT } from "./GarpRegistry.sys.mjs";

export class GarpConnection {
  constructor(transport, service) {
    this.transport = transport;
    this.service = service;
    this.outStream = transport.openOutputStream(0, 0, 0);
    this.inStream = transport.openInputStream(0, 0, 0);
    this.buffer = new Uint8Array(0);
    this.closed = false;

    // §14.1 server-side connection state.
    this.state = "NEW";
    this.authenticated = false;

    this.peerOfferedCapabilities = false; // receiver has validated peer CAPABILITIES
    this.ourEffectivePayloadLimit = GARP_HANDSHAKE_LIMIT;

    this.lastActivity = Date.now();
    this.lastInboundAuthenticatedTime = 0;
    this.lastOutboundProtocolTime = Date.now();

    this.clientName = null;
    this.clientVersion = null;
    this.clientNonceBytes = null;
    this.serverNonceBytes = null;
    this.offeredFeatures = [];
    this.finalFeatures = [];
    this.selectedSemanticVersion = "1.24";
    this.selectedWireVersion = "0x00";

    this.dispatchQueue = Promise.resolve();

    this.pump = Cc["@mozilla.org/network/input-stream-pump;1"].createInstance(Ci.nsIInputStreamPump);
    this.pump.init(this.inStream, 0, 0, false);
    this.pump.asyncRead(this);
  }

  onStartRequest() {}
  onDataAvailable(_req, stream, _off, count) {
    if (this.closed) return;
    const bin = Cc["@mozilla.org/binaryinputstream;1"].createInstance(Ci.nsIBinaryInputStream);
    bin.setInputStream(stream);
    const bytes = new Uint8Array(bin.readByteArray(count));
    this.lastActivity = Date.now();
    this.append(bytes);
    this.processFrames();
  }
  onStopRequest() { this.close(); }

  append(bytes) {
    const combined = new Uint8Array(this.buffer.length + bytes.length);
    combined.set(this.buffer, 0);
    combined.set(bytes, this.buffer.length);
    this.buffer = combined;
  }

  processFrames() {
    while (!this.closed) {
      if (this.buffer.length < 48) return;
      const view = new DataView(this.buffer.buffer, this.buffer.byteOffset, this.buffer.byteLength);
      const headerLen = view.getUint16(6, false);
      const payloadLen = view.getUint32(8, false);
      if (headerLen !== 48) { this.fail(new GarpError(GarpErrorCode.INVALID_ARGUMENT, "bad header_len")); return; }
      const frameLen = headerLen + payloadLen;
      if (this.buffer.length < frameLen) return;
      const frame = this.buffer.slice(0, frameLen);
      this.buffer = this.buffer.slice(frameLen);
      let decoded;
      try {
        decoded = decodeFrame(frame, { effectiveLimit: this.ourEffectivePayloadLimit });
      } catch (error) {
        this.fail(error);
        return;
      }
      this.dispatchQueue = this.dispatchQueue
        .then(() => {
          if (this.closed) return;
          return this.service.handleGarpMessage(this, decoded);
        })
        .catch(error => this.fail(error));
    }
  }

  send(type, payload = {}, options = {}) {
    if (this.closed) return false;
    try {
      const { envelope } = encodeEnvelope({
        type,
        requestId: options.request_id ?? null,
        sessionId: options.session_id ?? null,
        sequence: options.sequence ?? null,
        payload,
      });
      const frame = encodeFrame(envelope, { effectiveLimit: GARP_HANDSHAKE_LIMIT });
      const out = Cc["@mozilla.org/binaryoutputstream;1"].createInstance(Ci.nsIBinaryOutputStream);
      out.setOutputStream(this.outStream);
      out.writeByteArray(frame, frame.length);
      this.lastOutboundProtocolTime = Date.now();
      return true;
    } catch (error) {
      this.fail(error);
      return false;
    }
  }

  fail(error) {
    if (this.closed) return;
    // §26 scoping: connection-scoped ERROR if unauthenticated, else scoped to command/session.
    try {
      this.send("ERROR", {
        code: error?.code || GarpErrorCode.INTERNAL_ERROR_PLACEHOLDER_UNUSED,
        message: error?.message || String(error),
      }, {
        request_id: error?.requestId ?? null,
        session_id: error?.sessionId ?? null,
      });
    } catch (_) {}
    this.close();
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    try { this.pump.cancel(0x804B0002); } catch (_) {}
    try { this.inStream.close(); } catch (_) {}
    try { this.outStream.close(); } catch (_) {}
    this.service.removeConnection(this);
  }
}