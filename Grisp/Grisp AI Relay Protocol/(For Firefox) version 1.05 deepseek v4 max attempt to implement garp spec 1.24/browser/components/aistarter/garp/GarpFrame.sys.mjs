// GARP/1.24 framing, envelope encode/decode, validation order. See §6–§12.

import {
  GARP_FIXED_HEADER_LENGTH,
  GARP_HANDSHAKE_LIMIT,
  GARP_SEMANTIC_VERSION,
  GARP_WIRE_VERSION_BYTE,
  messageTypeId,
  messageTypeName,
} from "./GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder("utf-8", { fatal: true });

const NIL_UUID_BYTES = new Uint8Array(16);

export function uuidToBytes(value) {
  if (value == null) return NIL_UUID_BYTES.slice();
  const text = String(value).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(text)) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `invalid UUID: ${value}`);
  }
  const hex = text.replaceAll("-", "");
  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  return bytes;
}

export function bytesToUuid(bytes, offset) {
  for (let i = 0; i < 16; i++) if (bytes[offset + i] !== 0) {
    const hex = [];
    for (let j = 0; j < 16; j++) hex.push(bytes[offset + j].toString(16).padStart(2, "0"));
    const s = hex.join("");
    return `${s.slice(0,8)}-${s.slice(8,12)}-${s.slice(12,16)}-${s.slice(16,20)}-${s.slice(20)}`;
  }
  return null;
}

export function isoNow() {
  return new Date().toISOString();
}

function hasDuplicateKeys(jsonText) {
  // Lightweight scanner that fails if any object in the JSON text contains a
  // duplicate member name. See §9.2.
  let i = 0;
  const n = jsonText.length;

  const skipWs = () => { while (i < n && /\s/.test(jsonText[i])) i++; };

  const readString = () => {
    if (jsonText[i] !== '"') throw new Error("expected string");
    i++;
    let s = "";
    while (i < n && jsonText[i] !== '"') {
      if (jsonText[i] === "\\") {
        s += jsonText[i + 1];
        i += 2;
      } else {
        s += jsonText[i++];
      }
    }
    if (jsonText[i] !== '"') throw new Error("unterminated string");
    i++;
    return s;
  };

  const readValue = () => {
    skipWs();
    const c = jsonText[i];
    if (c === "{") {
      i++;
      const keys = new Set();
      skipWs();
      if (jsonText[i] === "}") { i++; return; }
      for (;;) {
        skipWs();
        const key = readString();
        if (keys.has(key)) throw new Error(`duplicate key: ${key}`);
        keys.add(key);
        skipWs();
        if (jsonText[i] !== ":") throw new Error("expected :");
        i++;
        readValue();
        skipWs();
        if (jsonText[i] === ",") { i++; continue; }
        if (jsonText[i] === "}") { i++; return; }
        throw new Error("expected , or }");
      }
    } else if (c === "[") {
      i++;
      skipWs();
      if (jsonText[i] === "]") { i++; return; }
      for (;;) {
        readValue();
        skipWs();
        if (jsonText[i] === ",") { i++; continue; }
        if (jsonText[i] === "]") { i++; return; }
        throw new Error("expected , or ]");
      }
    } else if (c === '"') {
      readString();
    } else if (c === "t") {
      if (jsonText.substr(i, 4) !== "true") throw new Error("expected true");
      i += 4;
    } else if (c === "f") {
      if (jsonText.substr(i, 5) !== "false") throw new Error("expected false");
      i += 5;
    } else if (c === "n") {
      if (jsonText.substr(i, 4) !== "null") throw new Error("expected null");
      i += 4;
    } else if (c === "-" || (c >= "0" && c <= "9")) {
      while (i < n && /[0-9eE+\-.]/.test(jsonText[i])) i++;
    } else {
      throw new Error("unexpected token");
    }
  };

  readValue();
  skipWs();
  if (i !== n) throw new Error("trailing data");
}

export function encodeEnvelope({ type, requestId, sessionId, sequence, payload }) {
  const numericType = typeof type === "number" ? type : messageTypeId(type);
  const typeName = messageTypeName(numericType);
  if (!numericType || !typeName) {
    throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `unknown message type: ${type}`);
  }
  const envelope = {
    garp: GARP_SEMANTIC_VERSION,
    type: typeName,
    request_id: requestId ?? null,
    session_id: sessionId ?? null,
    timestamp: isoNow(),
    sequence: sequence ?? null,
    payload: payload ?? {},
  };
  return { numericType, envelope };
}

export function encodeFrame(envelope, options = {}) {
  const numericType = messageTypeId(envelope.type);
  if (!numericType) {
    throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `unknown type: ${envelope.type}`);
  }
  const payloadBytes = textEncoder.encode(JSON.stringify(envelope));
  const limit = options.effectiveLimit ?? GARP_HANDSHAKE_LIMIT;
  if (payloadBytes.length > limit) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "frame payload exceeds effective limit");
  }
  const frame = new Uint8Array(GARP_FIXED_HEADER_LENGTH + payloadBytes.length);
  const view = new DataView(frame.buffer);
  frame[0] = 0x47; frame[1] = 0x41; frame[2] = 0x52; frame[3] = 0x50;
  view.setUint8(4, GARP_WIRE_VERSION_BYTE);
  view.setUint8(5, 0);
  view.setUint16(6, GARP_FIXED_HEADER_LENGTH, false);
  view.setUint32(8, payloadBytes.length, false);
  view.setUint16(12, numericType, false);
  view.setUint16(14, 0, false);
  frame.set(uuidToBytes(envelope.request_id), 16);
  frame.set(uuidToBytes(envelope.session_id), 32);
  frame.set(payloadBytes, GARP_FIXED_HEADER_LENGTH);
  return frame;
}

export function readHeader(frame) {
  if (frame.length < GARP_FIXED_HEADER_LENGTH) {
    throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "frame shorter than 48-byte header");
  }
  if (frame[0] !== 0x47 || frame[1] !== 0x41 || frame[2] !== 0x52 || frame[3] !== 0x50) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "invalid GARP magic");
  }
  if (frame[4] !== GARP_WIRE_VERSION_BYTE) {
    throw new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, `wire version ${frame[4]}`);
  }
  const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength);
  const headerLen = view.getUint16(6, false);
  if (headerLen !== GARP_FIXED_HEADER_LENGTH) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `header_len ${headerLen}`);
  }
  const payloadLen = view.getUint32(8, false);
  if (frame[5] !== 0) {
    throw new GarpError(GarpErrorCode.UNSUPPORTED_FEATURE, "flags must be zero in base GARP");
  }
  if (frame[14] !== 0 || frame[15] !== 0) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "reserved header field nonzero");
  }
  return {
    headerLen,
    payloadLen,
    messageType: view.getUint16(12, false),
    requestUuid: bytesToUuid(frame, 16),
    sessionUuid: bytesToUuid(frame, 32),
  };
}

export function decodeFrame(frame, options = {}) {
  const header = readHeader(frame);
  const limit = options.effectiveLimit ?? GARP_HANDSHAKE_LIMIT;
  if (header.payloadLen > limit) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "payload exceeds effective limit");
  }
  if (GARP_FIXED_HEADER_LENGTH + header.payloadLen !== frame.length) {
    throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "payload length mismatch");
  }
  const payloadBytes = frame.subarray(GARP_FIXED_HEADER_LENGTH);
  const jsonText = textDecoder.decode(payloadBytes);
  try {
    hasDuplicateKeys(jsonText);
  } catch (e) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `duplicate JSON keys: ${e.message}`);
  }
  let envelope;
  try {
    envelope = JSON.parse(jsonText);
  } catch (e) {
    throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, `invalid JSON: ${e.message}`);
  }
  // §11 required envelope shape.
  if (!envelope || typeof envelope !== "object" || Array.isArray(envelope)) {
    throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "envelope must be an object");
  }
  for (const key of Object.keys(envelope)) {
    if (!["garp", "type", "request_id", "session_id", "timestamp", "sequence", "payload"].includes(key)) {
      throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, `unknown envelope member: ${key}`);
    }
  }
  if (envelope.garp !== GARP_SEMANTIC_VERSION) {
    throw new GarpError(GarpErrorCode.UNSUPPORTED_VERSION, `unsupported semantic version ${envelope.garp}`);
  }
  const typeName = messageTypeName(header.messageType);
  if (!typeName) {
    throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `unknown message code 0x${header.messageType.toString(16)}`);
  }
  if (envelope.type !== typeName) {
    throw new GarpError(GarpErrorCode.HEADER_JSON_MISMATCH, `envelope type ${envelope.type} != ${typeName}`);
  }
  const envelopeRequestId = envelope.request_id === null ? null : String(envelope.request_id);
  const envelopeSessionId = envelope.session_id === null ? null : String(envelope.session_id);
  if (envelopeRequestId !== header.requestUuid) {
    throw new GarpError(GarpErrorCode.HEADER_JSON_MISMATCH, "request UUID mismatch");
  }
  if (envelopeSessionId !== header.sessionUuid) {
    throw new GarpError(GarpErrorCode.HEADER_JSON_MISMATCH, "session UUID mismatch");
  }
  if (envelope.payload === null || typeof envelope.payload !== "object" || Array.isArray(envelope.payload)) {
    throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "payload must be an object");
  }
  return {
    type: typeName,
    numericType: header.messageType,
    requestId: envelopeRequestId,
    sessionId: envelopeSessionId,
    sequence: envelope.sequence,
    timestamp: envelope.timestamp,
    payload: envelope.payload,
    envelope,
  };
}