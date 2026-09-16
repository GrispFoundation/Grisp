import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";

import { GARP_SEMANTIC_VERSION, GARP_WIRE_VERSION } from "./GarpRegistry.sys.mjs";

import {
    base64UrlDecode,
    base64UrlEncode,
    constantTimeEqualBytes,
    encodeTranscript,
    sha256,
    hmacSha256,
    sortedUtf8,
} from "./GarpUtil.sys.mjs";

const FEATURE_RE = /^!?[a-z0-9][a-z0-9._-]{0,127}$/;

export function validateAndCanonicaliseFeatures(list) {
    if (!Array.isArray(list))
        throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "features must be an array");
    const seen = new Set();
    const out = [];
    for (const raw of list) {
        if (typeof raw !== "string" || !FEATURE_RE.test(raw))
            throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "invalid feature token");
        const required = raw.startsWith("!"), canonical = required ? raw.slice(1) : raw;
        if (seen.has(canonical))
            throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, `duplicate feature: ${canonical}`);
        seen.add(canonical);
        out.push({ raw, canonical, required });
    }
    const sorted = out.slice().sort((a, b) => {
        const aa = new TextEncoder().encode(a.raw), bb = new TextEncoder().encode(b.raw);
        for (let i = 0; i < Math.min(aa.length, bb.length); i++)
            if (aa[i] !== bb[i])
                return aa[i] - bb[i];
        return aa.length - bb.length;
    });
    for (let i = 0; i < out.length; i++)
        if (out[i].raw !== sorted[i].raw)
            throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, "features must be UTF-8 byte sorted");
    return out;
}

export function negotiateFeatures(offered, supported) {
    const set = new Set(supported);
    const out = [];
    for (const f of offered) {
        if (set.has(f.canonical))
            out.push(f.required ? `!${f.canonical}` : f.canonical);
        else if (f.required)
            throw new GarpError(GarpErrorCode.UNSUPPORTED_FEATURE, `Required feature unsupported: ${f.canonical}`);
    }
    return sortedUtf8(out);
}

export function buildTranscript(args) {
    return encodeTranscript(args.domain, args.clientNonceBytes, args.serverNonceBytes, args.selectedSemanticVersion, args.selectedWireVersion, args.offeredFeatures, args.finalFeatures, args.clientName, args.clientVersion, args.serverName, args.serverVersion);
}

export async function proof(secret, transcript) {
    return hmacSha256(secret, transcript);
}

export function decodeNonce(value) {
    return base64UrlDecode(value, 16);
}

export function encodeNonce(bytes) {
    return base64UrlEncode(bytes);
}

export async function transcriptReplayKey(args) {
    return sha256(buildTranscript({ ...args, domain: "" }));
}

export function requireExactVersion(version, wire) {
    if (version !== GARP_SEMANTIC_VERSION)
        throw new GarpError(GarpErrorCode.UNSUPPORTED_VERSION, "Unsupported semantic version");
    if (wire !== GARP_WIRE_VERSION)
        throw new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, "Unsupported wire version");
}

export function verifyProof(expected, presented) {
    if (!constantTimeEqualBytes(expected, presented))
        throw new GarpError(GarpErrorCode.AUTH_FAILED, "Authentication proof failed");
}
