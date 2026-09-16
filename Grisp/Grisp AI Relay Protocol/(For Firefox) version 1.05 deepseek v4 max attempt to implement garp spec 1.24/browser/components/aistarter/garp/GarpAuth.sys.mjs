// GARP/1.24 authentication transcript and proof encoding. See §16 and §139.

import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder("utf-8", { fatal: true });

export function randomNonce16() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return bytes;
}

export function bytesToBase64URL(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

export function base64URLToBytes(value) {
  const text = String(value ?? "");
  if (text.length === 0 || /[^A-Za-z0-9\-_]/.test(text)) {
    throw new GarpError(GarpErrorCode.AUTH_FAILED, "Invalid Base64URL alphabet");
  }
  if (text.includes("=")) {
    throw new GarpError(GarpErrorCode.AUTH_FAILED, "Base64URL padding is not permitted");
  }
  const normal = text.replaceAll("-", "+").replaceAll("_", "/");
  let binary;
  try {
    binary = atob(normal);
  } catch (e) {
    throw new GarpError(GarpErrorCode.AUTH_FAILED, "Invalid Base64URL payload");
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function assertNonce16(value, fieldName) {
  const bytes = base64URLToBytes(value);
  if (bytes.length !== 16) {
    throw new GarpError(
      GarpErrorCode.AUTH_FAILED,
      `${fieldName} must decode to exactly 16 bytes`
    );
  }
  return bytes;
}

function u32be(value) {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, value >>> 0, false);
  return out;
}

function concat(parts) {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

function lengthPrefixed(bytesOrString) {
  const bytes =
    typeof bytesOrString === "string"
      ? textEncoder.encode(bytesOrString)
      : bytesOrString;
  return concat([u32be(bytes.length), bytes]);
}

function encodeFeatureSet(features) {
  const parts = [u32be(features.length)];
  for (const f of features) parts.push(lengthPrefixed(f));
  return concat(parts);
}

export function buildTranscript({
  domain,
  clientNonceBytes,
  serverNonceBytes,
  selectedSemanticVersion,
  selectedWireVersion,
  offeredFeatures,
  finalFeatures,
  clientName,
  clientVersion,
  serverName,
  serverVersion,
}) {
  return concat([
    lengthPrefixed(domain),
    lengthPrefixed(clientNonceBytes),
    lengthPrefixed(serverNonceBytes),
    lengthPrefixed(selectedSemanticVersion),
    lengthPrefixed(selectedWireVersion),
    encodeFeatureSet(offeredFeatures),
    encodeFeatureSet(finalFeatures),
    lengthPrefixed(clientName),
    lengthPrefixed(clientVersion),
    lengthPrefixed(serverName),
    lengthPrefixed(serverVersion),
  ]);
}

export async function hmacSha256(secretBytes, transcript) {
  const key = await crypto.subtle.importKey(
    "raw",
    secretBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, transcript);
  return new Uint8Array(sig);
}

export function constantTimeEqualBytes(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// Feature-name syntax and canonicalisation per §15.
const FEATURE_RE = /^!?[a-z0-9][a-z0-9._-]{0,127}$/;

export function validateAndCanonicaliseFeatures(list) {
  if (!Array.isArray(list)) {
    throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "features must be an array");
  }
  const seen = new Set();
  const out = [];
  for (const raw of list) {
    if (typeof raw !== "string" || !FEATURE_RE.test(raw)) {
      throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `invalid feature token: ${raw}`);
    }
    const required = raw.startsWith("!");
    const canonical = required ? raw.slice(1) : raw;
    if (seen.has(canonical)) {
      throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `duplicate feature: ${canonical}`);
    }
    seen.add(canonical);
    out.push({ canonical, required, raw });
  }
  // Sort by raw UTF-8 byte order of canonical name.
  out.sort((a, b) => {
    const ab = textEncoder.encode(a.canonical);
    const bb = textEncoder.encode(b.canonical);
    const n = Math.min(ab.length, bb.length);
    for (let i = 0; i < n; i++) {
      if (ab[i] !== bb[i]) return ab[i] - bb[i];
    }
    return ab.length - bb.length;
  });
  return out;
}

export function negotiateFeatures(offered, supported) {
  const supportedSet = new Set(supported);
  const finalSet = [];
  for (const entry of offered) {
    if (supportedSet.has(entry.canonical)) {
      finalSet.push(entry.required ? `!${entry.canonical}` : entry.canonical);
    } else if (entry.required) {
      throw new GarpError(
        GarpErrorCode.UNSUPPORTED_FEATURE,
        `required feature not supported: ${entry.canonical}`
      );
    }
  }
  return finalSet;
}