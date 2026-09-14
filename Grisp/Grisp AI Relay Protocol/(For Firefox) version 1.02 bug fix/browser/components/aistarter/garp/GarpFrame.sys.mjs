import {
  GARP_FIXED_HEADER_LENGTH,
  GARP_MAX_FRAME_SIZE,
  GARP_PROTOCOL,
  GARP_VERSION_BYTE,
  messageTypeId,
  messageTypeName,
} from "./GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder("utf-8", { fatal: true });

export function uuidToBytes(value) {
  const text = String(value || "").toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(text)) {
    return new Uint8Array(16);
  }
  const hex = text.replaceAll("-", "");
  const bytes = new Uint8Array(16);
  for (let index = 0; index < 16; index++) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

export function bytesToUuid(bytes, offset = 0) {
  let allZero = true;
  for (let index = 0; index < 16; index++) {
    if (bytes[offset + index] !== 0) {
      allZero = false;
      break;
    }
  }
  if (allZero) {
    return null;
  }
  const hex = [];
  for (let index = 0; index < 16; index++) {
    hex.push(bytes[offset + index].toString(16).padStart(2, "0"));
  }
  const text = hex.join("");
  return `${text.slice(0, 8)}-${text.slice(8, 12)}-${text.slice(12, 16)}-${text.slice(16, 20)}-${text.slice(20)}`;
}

export function encodeGarpMessage(type, payload = {}, options = {}) {
  const numericType = typeof type === "number" ? type : messageTypeId(type);
  const typeName = messageTypeName(numericType);
  if (!numericType || !typeName) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, `Unknown GARP message type: ${type}`);
  }

  const body = {
    protocol: GARP_PROTOCOL,
    type: typeName,
    ...(options.request_id ? { request_id: options.request_id } : {}),
    ...(options.session_id ? { session_id: options.session_id } : {}),
    ...(options.tab_id ? { tab_id: options.tab_id } : {}),
    ...(options.message_id ? { message_id: options.message_id } : {}),
    ...(options.sequence != null ? { sequence: options.sequence } : {}),
    ...(options.page_generation != null ? { page_generation: options.page_generation } : {}),
    ...(options.timestamp ? { timestamp: options.timestamp } : {}),
    ...(payload !== undefined ? { payload } : {}),
  };

  const payloadBytes = textEncoder.encode(JSON.stringify(body));
  if (payloadBytes.length > GARP_MAX_FRAME_SIZE) {
    throw new GarpError(GarpErrorCode.FRAME_TOO_LARGE, "GARP payload exceeds maximum frame size");
  }

  const frame = new Uint8Array(GARP_FIXED_HEADER_LENGTH + payloadBytes.length);
  const view = new DataView(frame.buffer);
  frame.set([0x47, 0x41, 0x52, 0x50], 0);
  view.setUint8(4, GARP_VERSION_BYTE);
  view.setUint8(5, options.flags || 0);
  view.setUint16(6, GARP_FIXED_HEADER_LENGTH, false);
  view.setUint32(8, payloadBytes.length, false);
  view.setUint16(12, numericType, false);
  view.setUint16(14, 0, false);
  frame.set(uuidToBytes(options.request_id), 16);
  frame.set(uuidToBytes(options.session_id), 32);
  frame.set(payloadBytes, GARP_FIXED_HEADER_LENGTH);
  return frame;
}

export function decodeGarpFrame(frame) {
  if (frame.length < GARP_FIXED_HEADER_LENGTH) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "GARP frame shorter than fixed header");
  }

  if (frame[0] !== 0x47 || frame[1] !== 0x41 || frame[2] !== 0x52 || frame[3] !== 0x50) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Invalid GARP magic");
  }

  const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength);
  if (view.getUint8(4) !== GARP_VERSION_BYTE) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, `Unsupported GARP version byte 0x${view.getUint8(4).toString(16)}`);
  }

  const headerLength = view.getUint16(6, false);
  const payloadLength = view.getUint32(8, false);
  if (headerLength < GARP_FIXED_HEADER_LENGTH) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Invalid GARP header length");
  }
  if (frame[14] !== 0 || frame[15] !== 0) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Reserved header field is nonzero");
  }
  if (headerLength + payloadLength !== frame.length) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "GARP payload length mismatch");
  }
  if (payloadLength > GARP_MAX_FRAME_SIZE) {
    throw new GarpError(GarpErrorCode.FRAME_TOO_LARGE, "GARP payload exceeds maximum frame size");
  }

  const numericType = view.getUint16(12, false);
  const type = messageTypeName(numericType);
  if (!type) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, `Unknown GARP message type 0x${numericType.toString(16)}`);
  }

  let json;
  try {
    json = JSON.parse(textDecoder.decode(frame.subarray(headerLength)));
  } catch (error) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, `Invalid UTF-8/JSON payload: ${error.message}`);
  }

  if (!json || typeof json !== "object") {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "GARP payload must be a JSON object");
  }
  if (json.protocol !== GARP_PROTOCOL || json.type !== type) {
    throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "GARP JSON protocol/type does not match binary header");
  }

  return {
    numericType,
    type,
    request_id: bytesToUuid(frame, 16),
    session_id: bytesToUuid(frame, 32),
    message: json,
  };
}
