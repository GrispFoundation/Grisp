import { encodeGarpMessage, decodeGarpFrame } from "./GarpFrame.sys.mjs";
import { GarpError } from "./GarpErrors.sys.mjs";

export class GarpConnection {
  constructor(transport, service) {
    this.transport = transport;
    this.service = service;
    this.outStream = transport.openOutputStream(0, 0, 0);
    this.inStream = transport.openInputStream(0, 0, 0);
    this.buffer = new Uint8Array(0);
    this.closed = false;
    this.authenticated = false;
    this.authState = "CONNECTED";
    this.lastActivity = Date.now();
    this.dispatchQueue = Promise.resolve();

    this.pump = Cc["@mozilla.org/network/input-stream-pump;1"].createInstance(Ci.nsIInputStreamPump);
    this.pump.init(this.inStream, 0, 0, false);
    this.pump.asyncRead(this);
  }

  onStartRequest() {}

  onDataAvailable(_request, stream, _offset, count) {
    if (this.closed) return;
    const binaryStream = Cc["@mozilla.org/binaryinputstream;1"].createInstance(Ci.nsIBinaryInputStream);
    binaryStream.setInputStream(stream);
    const bytes = new Uint8Array(binaryStream.readByteArray(count));
    this.lastActivity = Date.now();
    this.dispatchQueue = Promise.resolve();
    this.appendBytes(bytes);
    this.processFrames();
  }

  onStopRequest(_request, _status) {
    this.close();
  }

  appendBytes(bytes) {
    const combined = new Uint8Array(this.buffer.length + bytes.length);
    combined.set(this.buffer, 0);
    combined.set(bytes, this.buffer.length);
    this.buffer = combined;
  }

  processFrames() {
    while (!this.closed) {
      if (this.buffer.length < 48) return;
      const view = new DataView(this.buffer.buffer, this.buffer.byteOffset, this.buffer.byteLength);
      const headerLength = view.getUint16(6, false);
      const payloadLength = view.getUint32(8, false);
      const frameLength = headerLength + payloadLength;
      if (headerLength < 48 || frameLength < headerLength || frameLength > 16 * 1024 * 1024 + headerLength) {
        this.fail(new GarpError("PROTOCOL_ERROR", "Invalid or oversized GARP frame"));
        return;
      }
      if (this.buffer.length < frameLength) return;
      const frame = this.buffer.slice(0, frameLength);
      this.buffer = this.buffer.slice(frameLength);
      try {
        const decoded = decodeGarpFrame(frame);
        this.dispatchQueue = this.dispatchQueue
          .then(() => this.service.handleGarpMessage(this, decoded))
          .catch(error => this.fail(error));
      } catch (error) {
        this.fail(error);
        return;
      }
    }
  }

  send(type, payload = {}, options = {}) {
    if (this.closed) return false;
    try {
      const bytes = encodeGarpMessage(type, payload, options);
      const output = Cc["@mozilla.org/binaryoutputstream;1"].createInstance(Ci.nsIBinaryOutputStream);
      output.setOutputStream(this.outStream);
      output.writeByteArray(bytes, bytes.length);
      return true;
    } catch (error) {
      this.fail(error);
      return false;
    }
  }

  fail(error) {
    try {
      this.send("error", {
        code: error?.code || "INTERNAL_ERROR",
        message: error?.message || String(error),
        retryable: !!error?.retryable,
        state: error?.state || "ERROR",
        ...(error?.provider ? { provider: error.provider } : {}),
        ...(error?.details ? { details: error.details } : {}),
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
