import { GARP_UINT64_MAX } from "./GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";

export const textEncoder = new TextEncoder();
export const textDecoder = new TextDecoder("utf-8", { fatal: true });

export function monotonicNow() {
  return globalThis.performance?.now?.() ?? Date.now();
}

export function byteLength(value) {
  return textEncoder.encode(String(value ?? "")).length;
}

export function utf8ByteCompare(left, right) {
  const a = textEncoder.encode(String(left));
  const b = textEncoder.encode(String(right));
  const count = Math.min(a.length, b.length);
  for (let i = 0; i < count; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return a.length - b.length;
}

export function sortedUtf8(values) {
  return [...values].sort(utf8ByteCompare);
}

export function isUuid(value) {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

export function isNilUuid(value) {
  return value === null || value === "00000000-0000-0000-0000-000000000000";
}

export function uuid() {
  return crypto.randomUUID();
}

export function uuidToBytes(value) {
  if (value === null || value === undefined) return new Uint8Array(16);
  if (!isUuid(value)) throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `Invalid UUID: ${value}`);
  const hex = value.replaceAll("-", "").toLowerCase();
  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

export function bytesToUuid(bytes, offset = 0) {
  let allZero = true;
  for (let i = 0; i < 16; i++) {
    if (bytes[offset + i] !== 0) { allZero = false; break; }
  }
  if (allZero) return null;
  const hex = [];
  for (let i = 0; i < 16; i++) hex.push(bytes[offset + i].toString(16).padStart(2, "0"));
  const text = hex.join("");
  return `${text.slice(0, 8)}-${text.slice(8, 12)}-${text.slice(12, 16)}-${text.slice(16, 20)}-${text.slice(20)}`;
}

export function uint64(value, fieldName = "uint64") {
  const text = String(value);
  if (!/^(0|[1-9][0-9]{0,19})$/.test(text)) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `${fieldName} must be a uint64-string`);
  }
  const result = BigInt(text);
  if (result > GARP_UINT64_MAX) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `${fieldName} exceeds uint64`);
  }
  return result;
}

export function u32(value, fieldName = "uint32") {
  if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `${fieldName} must be uint32`);
  }
  return value;
}

export function durationMs(value, fieldName, max = 864000000n) {
  const parsed = uint64(value, fieldName);
  if (parsed > max) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `${fieldName} exceeds allowed duration`);
  }
  return parsed;
}

export function base64UrlEncode(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

export function base64UrlDecode(text, expectedLength = null) {
  if (typeof text !== "string" || !/^[A-Za-z0-9_-]*$/.test(text)) {
    throw new GarpError(GarpErrorCode.AUTH_FAILED, "Invalid Base64URL nonce/proof");
  }
  if (text.length % 4 === 1) throw new GarpError(GarpErrorCode.AUTH_FAILED, "Invalid Base64URL length");
  const padded = text.replaceAll("-", "+").replaceAll("_", "/") + "===".slice((text.length + 3) % 4);
  let binary;
  try { binary = atob(padded); } catch (_) { throw new GarpError(GarpErrorCode.AUTH_FAILED, "Invalid Base64URL encoding"); }
  const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
  if (expectedLength !== null && bytes.length !== expectedLength) {
    throw new GarpError(GarpErrorCode.AUTH_FAILED, "Decoded value has invalid length");
  }
  return bytes;
}

export function constantTimeEqualBytes(a, b) {
  if (!(a instanceof Uint8Array) || !(b instanceof Uint8Array)) return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

export async function hmacSha256(keyBytes, dataBytes) {
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, dataBytes));
}

export function appendU32(list, value) {
  const view = new DataView(new ArrayBuffer(4));
  view.setUint32(0, value, false);
  list.push(...new Uint8Array(view.buffer));
}

export function appendBytes(list, bytes) {
  appendU32(list, bytes.length);
  list.push(...bytes);
}

export function encodeTranscript(domain, clientNonce, serverNonce, selectedVersion, selectedWireVersion, offeredFeatures, finalFeatures, clientName, clientVersion, serverName, serverVersion) {
  const list = [];
  appendBytes(list, textEncoder.encode(domain));
  appendBytes(list, clientNonce);
  appendBytes(list, serverNonce);
  appendBytes(list, textEncoder.encode(selectedVersion));
  appendBytes(list, textEncoder.encode(selectedWireVersion));
  appendU32(list, offeredFeatures.length);
  for (const feature of offeredFeatures) appendBytes(list, textEncoder.encode(feature));
  appendU32(list, finalFeatures.length);
  for (const feature of finalFeatures) appendBytes(list, textEncoder.encode(feature));
  appendBytes(list, textEncoder.encode(clientName));
  appendBytes(list, textEncoder.encode(clientVersion));
  appendBytes(list, textEncoder.encode(serverName));
  appendBytes(list, textEncoder.encode(serverVersion));
  return new Uint8Array(list);
}

export function encodeTranscriptCore(clientNonce, serverNonce, selectedVersion, selectedWireVersion, offeredFeatures, finalFeatures, clientName, clientVersion, serverName, serverVersion) {
  const list = [];
  appendBytes(list, clientNonce);
  appendBytes(list, serverNonce);
  appendBytes(list, textEncoder.encode(selectedVersion));
  appendBytes(list, textEncoder.encode(selectedWireVersion));
  appendU32(list, offeredFeatures.length);
  for (const feature of offeredFeatures) appendBytes(list, textEncoder.encode(feature));
  appendU32(list, finalFeatures.length);
  for (const feature of finalFeatures) appendBytes(list, textEncoder.encode(feature));
  appendBytes(list, textEncoder.encode(clientName));
  appendBytes(list, textEncoder.encode(clientVersion));
  appendBytes(list, textEncoder.encode(serverName));
  appendBytes(list, textEncoder.encode(serverVersion));
  return new Uint8Array(list);
}
