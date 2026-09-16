import {
  GARP_APPLICATION_LIMIT_DEFAULT,
  GARP_FIXED_HEADER_LENGTH,
  GARP_HANDSHAKE_LIMIT,
  GARP_MAX_ERROR_DETAILS_BYTES,
  GARP_MAX_DIAGNOSTIC_DETAILS_BYTES,
  GARP_PROTOCOL,
  GARP_SEMANTIC_VERSION,
  GARP_VERSION_BYTE,
  messageTypeId,
  messageTypeName,
} from "./GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";
import { assertNoDuplicateObjectMembers } from "./GarpJson.sys.mjs";
import { textDecoder, textEncoder, uuidToBytes, bytesToUuid } from "./GarpUtil.sys.mjs";
import { validateEnvelope } from "./GarpSchema.sys.mjs";

export function encodeGarpEnvelope(envelope, { enforceMaxPayload = GARP_APPLICATION_LIMIT_DEFAULT } = {}) {
  const text = JSON.stringify(envelope);
  const payloadBytes = textEncoder.encode(text);
  if (payloadBytes.length > enforceMaxPayload) throw new GarpError(GarpErrorCode.FRAME_TOO_LARGE, "GARP payload exceeds negotiated limit");
  validateEnvelope(envelope, envelope.type);
  const numericType = messageTypeId(envelope.type);
  if (!numericType) throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `Unknown GARP message type ${envelope.type}`);
  const frame = new Uint8Array(GARP_FIXED_HEADER_LENGTH + payloadBytes.length);
  const view = new DataView(frame.buffer);
  frame.set([0x47, 0x41, 0x52, 0x50], 0);
  view.setUint8(4, GARP_VERSION_BYTE);
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

export function encodeGarpMessage(type, payload = {}, options = {}) {
  const now = options.timestamp || new Date().toISOString();
  const envelope = {
    garp: GARP_SEMANTIC_VERSION,
    type: typeof type === "number" ? messageTypeName(type) : String(type).toUpperCase(),
    request_id: options.request_id ?? null,
    session_id: options.session_id ?? null,
    timestamp: now,
    sequence: options.sequence ?? null,
    payload,
  };
  validateEnvelope(envelope, envelope.type);
  return encodeGarpEnvelope(envelope, { enforceMaxPayload: options.maxPayloadBytes ?? GARP_APPLICATION_LIMIT_DEFAULT });
}

export function decodeGarpFrame(frame) {
  if (!(frame instanceof Uint8Array)) frame = new Uint8Array(frame);
  if (frame.length < GARP_FIXED_HEADER_LENGTH) throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "GARP frame shorter than fixed header");
  if (frame[0] !== 0x47 || frame[1] !== 0x41 || frame[2] !== 0x52 || frame[3] !== 0x50) throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Invalid GARP magic");
  const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength);
  const wireVersion = view.getUint8(4);
  if (wireVersion !== GARP_VERSION_BYTE) throw new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, `Unsupported wire version 0x${wireVersion.toString(16).padStart(2, "0")}`);
  const headerLength = view.getUint16(6, false);
  if (headerLength !== GARP_FIXED_HEADER_LENGTH) throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "GARP header length must be exactly 48");
  const payloadLength = view.getUint32(8, false);
  if (frame.length !== headerLength + payloadLength) throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "GARP payload length mismatch");
  if (view.getUint8(5) !== 0) throw new GarpError(GarpErrorCode.UNSUPPORTED_FEATURE, "Unknown or unnegotiated GARP flag bit");
  if (view.getUint16(14, false) !== 0) throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Reserved header field is nonzero");
  const numericType = view.getUint16(12, false);
  const type = messageTypeName(numericType);
  if (!type) throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `Unknown GARP message type 0x${numericType.toString(16).padStart(4, "0")}`);
  let text;
  try { text = textDecoder.decode(frame.subarray(headerLength)); } catch (error) { throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `Invalid UTF-8 payload: ${error.message}`); }
  try { assertNoDuplicateObjectMembers(text); } catch (error) { throw error; }
  let json;
  try { json = JSON.parse(text); } catch (error) { throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `Invalid JSON payload: ${error.message}`); }
  const requestId = bytesToUuid(frame, 16);
  const sessionId = bytesToUuid(frame, 32);
  if (!json || typeof json.type !== "string" || !messageTypeId(json.type)) throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, "Unknown envelope message type");
  validateEnvelope(json, type, { request_id: requestId, session_id: sessionId });
  return { numericType, type, request_id: requestId, session_id: sessionId, message: json, payloadLength };
}

export function peekHeader(buffer) {
  if (buffer.length < GARP_FIXED_HEADER_LENGTH) return null;
  const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
  return {
    wireVersion: view.getUint8(4),
    flags: view.getUint8(5),
    headerLength: view.getUint16(6, false),
    payloadLength: view.getUint32(8, false),
    messageType: view.getUint16(12, false),
  };
}
