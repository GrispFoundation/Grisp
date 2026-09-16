import {
    GARP_FIXED_HEADER_LENGTH,
    GARP_SEMANTIC_VERSION,
    GARP_VERSION_BYTE,
    messageTypeId,
    messageTypeName,
} from "./GarpRegistry.sys.mjs";

import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";

import { assertNoDuplicateObjectMembers } from "./GarpJson.sys.mjs";

import { textEncoder, textDecoder, uuidToBytes, bytesToUuid } from "./GarpUtil.sys.mjs";

import { validateEnvelope } from "./GarpSchema.sys.mjs";

export function encodeGarpEnvelope(envelope, { enforceMaxPayload = 0xffffffff } = {}) {
    validateEnvelope(envelope, envelope.type);
    const text = JSON.stringify(envelope);
    const bytes = textEncoder.encode(text);
    if (bytes.length > enforceMaxPayload)
        throw new GarpError(GarpErrorCode.FRAME_TOO_LARGE, "GARP payload exceeds negotiated limit");
    const id = messageTypeId(envelope.type);
    if (!id)
        throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `Unknown message type ${envelope.type}`);
    const frame = new Uint8Array(GARP_FIXED_HEADER_LENGTH + bytes.length), v = new DataView(frame.buffer);
    frame.set([71, 65, 82, 80], 0);
    v.setUint8(4, GARP_VERSION_BYTE);
    v.setUint8(5, 0);
    v.setUint16(6, GARP_FIXED_HEADER_LENGTH, false);
    v.setUint32(8, bytes.length, false);
    v.setUint16(12, id, false);
    v.setUint16(14, 0, false);
    frame.set(uuidToBytes(envelope.request_id), 16);
    frame.set(uuidToBytes(envelope.session_id), 32);
    frame.set(bytes, GARP_FIXED_HEADER_LENGTH);
    return frame;
}

export function encodeGarpMessage(type, payload = {}, options = {}) {
    const envelope = { garp: GARP_SEMANTIC_VERSION, type: typeof type === "number" ? messageTypeName(type) : String(type).toUpperCase(), request_id: options.request_id ?? null, session_id: options.session_id ?? null, timestamp: options.timestamp || new Date().toISOString(), sequence: options.sequence ?? null, payload };
    return encodeGarpEnvelope(envelope, { enforceMaxPayload: options.maxPayloadBytes ?? 0xffffffff });
}

export function peekHeader(buffer) {
    if (buffer.length < GARP_FIXED_HEADER_LENGTH)
        return null;
    const v = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    return { wireVersion: v.getUint8(4), flags: v.getUint8(5), headerLength: v.getUint16(6, false), payloadLength: v.getUint32(8, false), messageType: v.getUint16(12, false) };
}

export function decodeGarpFrame(frame) {
    if (frame.length < GARP_FIXED_HEADER_LENGTH)
        throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Frame shorter than fixed header");
    const h = peekHeader(frame);
    if (frame[0] !== 71 || frame[1] !== 65 || frame[2] !== 82 || frame[3] !== 80)
        throw new GarpError(GarpErrorCode.PROTOCOL_ERROR, "Invalid GARP magic");
    if (h.wireVersion !== 0)
        throw new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, "Unsupported wire version");
    if (h.headerLength !== GARP_FIXED_HEADER_LENGTH)
        throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Header length must be 48");
    if (h.flags !== 0)
        throw new GarpError(GarpErrorCode.UNSUPPORTED_FEATURE, "Unknown or unnegotiated GARP flag bit");
    if (new DataView(frame.buffer, frame.byteOffset, frame.byteLength).getUint16(14, false) !== 0)
        throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Reserved header field is nonzero");
    if (frame.length !== GARP_FIXED_HEADER_LENGTH + h.payloadLength)
        throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "Payload length mismatch");
    const type = messageTypeName(h.messageType);
    if (!type)
        throw new GarpError(GarpErrorCode.UNKNOWN_MESSAGE_TYPE, `Unknown message type 0x${h.messageType.toString(16).padStart(4, "0")}`);
    let text;
    try {
        text = textDecoder.decode(frame.subarray(GARP_FIXED_HEADER_LENGTH));
    }
    catch (e) {
        throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `Invalid UTF-8 payload: ${e.message}`);
    }
    assertNoDuplicateObjectMembers(text);
    let json;
    try {
        json = JSON.parse(text);
    }
    catch (e) {
        throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `Invalid JSON payload: ${e.message}`);
    }
    const requestId = bytesToUuid(frame, 16), sessionId = bytesToUuid(frame, 32);
    if (!json || json.type !== type)
        throw new GarpError(GarpErrorCode.HEADER_JSON_MISMATCH, "Header/envelope type mismatch");
    validateEnvelope(json, type, { request_id: requestId, session_id: sessionId });
    return { numericType: h.messageType, type, request_id: requestId, session_id: sessionId, message: json, payloadLength: h.payloadLength };
}
