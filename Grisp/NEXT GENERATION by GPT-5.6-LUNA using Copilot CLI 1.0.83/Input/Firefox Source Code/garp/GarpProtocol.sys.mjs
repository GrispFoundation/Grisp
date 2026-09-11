const MAGIC = new TextEncoder().encode("GARP");
const VERSION = 1;
const HEADER_LENGTH = 48;

export const MessageType = Object.freeze({
  HELLO: 1, HELLO_ACK: 2, PING: 3, PONG: 4, CREATE_SESSION: 10,
  PROMPT: 20, PROMPT_ACK: 21, GENERATION_STARTED: 22,
  GENERATION_DELTA: 23, GENERATION_COMPLETED: 24, CANCEL_PROMPT: 25,
  CANCEL_ACK: 26, ERROR: 255
});

function uuidBytes(value) {
  const hex = value.replace(/-/g, "");
  if (!/^[0-9a-f]{32}$/i.test(hex)) throw new Error("invalid UUID");
  return Uint8Array.from(hex.match(/../g).map(pair => parseInt(pair, 16)));
}

function writeUuid(view, offset, value) {
  uuidBytes(value).forEach((byte, index) => view.setUint8(offset + index, byte));
}

export function encodeFrame(messageType, requestId, sessionId, payload,
  flags = 0) {
  const body = new TextEncoder().encode(JSON.stringify(payload));
  const frame = new ArrayBuffer(HEADER_LENGTH + body.length);
  const view = new DataView(frame);
  new Uint8Array(frame, 0, 4).set(MAGIC);
  view.setUint8(4, VERSION);
  view.setUint8(5, flags);
  view.setUint16(6, HEADER_LENGTH, false);
  view.setUint32(8, body.length, false);
  view.setUint16(12, messageType, false);
  view.setUint16(14, 0, false);
  writeUuid(view, 16, requestId);
  writeUuid(view, 32, sessionId);
  new Uint8Array(frame, HEADER_LENGTH).set(body);
  return frame;
}

export function decodeFrame(buffer, limits = { maxFrameSize: 16 * 1024 * 1024 }) {
  if (buffer.byteLength < HEADER_LENGTH) throw new Error("malformed frame");
  const view = new DataView(buffer);
  if (new TextDecoder().decode(new Uint8Array(buffer, 0, 4)) !== "GARP")
    throw new Error("invalid magic");
  if (view.getUint8(4) !== VERSION) throw new Error("unsupported protocol version");
  if (view.getUint16(6, false) !== HEADER_LENGTH) throw new Error("invalid header");
  const length = view.getUint32(8, false);
  if (length > limits.maxFrameSize || HEADER_LENGTH + length !== buffer.byteLength)
    throw new Error("invalid payload length");
  const payload = JSON.parse(new TextDecoder().decode(
    new Uint8Array(buffer, HEADER_LENGTH, length)));
  return { messageType: view.getUint16(12, false), payload };
}
