import assert from "node:assert/strict";
import { GarpError, GarpErrorCode } from "../browser/components/aistarter/garp/GarpErrors.sys.mjs";
import { encodeGarpMessage, decodeGarpFrame } from "../browser/components/aistarter/garp/GarpFrame.sys.mjs";
import { GarpMessageType, GARP_FIXED_HEADER_LENGTH, GARP_VERSION_BYTE } from "../browser/components/aistarter/garp/GarpRegistry.sys.mjs";
import {
  base64UrlEncode,
  encodeTranscript,
  hmacSha256,
  textEncoder,
} from "../browser/components/aistarter/garp/GarpUtil.sys.mjs";
import { validateMessagePayload } from "../browser/components/aistarter/garp/GarpSchema.sys.mjs";

const TEST_SECRET = textEncoder.encode("0123456789abcdef0123456789abcdef");
const CLIENT_NONCE = Uint8Array.from([
  0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
]);
const SERVER_NONCE = Uint8Array.from([
  0x10, 0x0f, 0x0e, 0x0d, 0x0c, 0x0b, 0x0a, 0x09,
  0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
]);

function hex(bytes) {
  return [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

function expectCode(fn, code) {
  assert.throws(fn, error => error instanceof GarpError && error.code === code);
}

async function testAuthenticationTranscript() {
  const common = [
    CLIENT_NONCE,
    SERVER_NONCE,
    "1.24",
    "0x00",
    ["!ext-pong"],
    ["!ext-pong"],
    "GARPClient",
    "1.24.0",
    "GarpGateway",
    "1.24.0",
  ];
  const clientTranscript = encodeTranscript("GARP/1.24/client-proof", ...common);
  const serverTranscript = encodeTranscript("GARP/1.24/server-proof", ...common);
  assert.equal(clientTranscript.length, 165);
  assert.equal(serverTranscript.length, 165);
  const clientProof = await hmacSha256(TEST_SECRET, clientTranscript);
  const serverProof = await hmacSha256(TEST_SECRET, serverTranscript);
  assert.equal(hex(clientProof), "e11893ab64943f5e603a9d5a96a21174c05433b42fe02319a9110c5d7e1e7d0b");
  assert.equal(base64UrlEncode(clientProof), "4RiTq2SUP15gOp1alqIRdMBUM7Qv4CMZqREMXX4efQs");
  assert.equal(hex(serverProof), "88569356861b9ffa5be720821ce4e9014c9fcc56829175ca80b01ba4c5fa71f2");
  assert.equal(base64UrlEncode(serverProof), "iFaTVoYbn_pb5yCCHOTpAUyfzFaCkXXKgLAbpMX6cfI");
}

function testPingVector() {
  const requestId = "00000000-0000-0000-0000-000000000001";
  const frame = encodeGarpMessage("PING", {}, {
    request_id: requestId,
    session_id: null,
    timestamp: "2026-01-01T00:00:00.000Z",
    sequence: null,
  });
  const expectedJson = "{\"garp\":\"1.24\",\"type\":\"PING\",\"request_id\":\"00000000-0000-0000-0000-000000000001\",\"session_id\":null,\"timestamp\":\"2026-01-01T00:00:00.000Z\",\"sequence\":null,\"payload\":{}}";
  assert.equal(frame.length - GARP_FIXED_HEADER_LENGTH, 167);
  assert.equal(new TextDecoder().decode(frame.subarray(GARP_FIXED_HEADER_LENGTH)), expectedJson);
  assert.equal(frame[4], GARP_VERSION_BYTE);
  assert.equal(frame[5], 0);
  assert.deepEqual([...frame.subarray(0, 16)], [
    0x47, 0x41, 0x52, 0x50, 0x00, 0x00, 0x00, 0x30,
    0x00, 0x00, 0x00, 0xa7, 0x00, 0x70, 0x00, 0x00,
  ]);
  const decoded = decodeGarpFrame(frame);
  assert.equal(decoded.type, "PING");
  assert.equal(decoded.request_id, requestId);
  assert.equal(decoded.session_id, null);
}

function testHeaderValidation() {
  const frame = encodeGarpMessage("PING", {}, {
    request_id: "00000000-0000-0000-0000-000000000002",
    session_id: null,
    timestamp: "2026-01-01T00:00:00.000Z",
    sequence: null,
  });

  const badMagic = frame.slice();
  badMagic[0] = 0;
  expectCode(() => decodeGarpFrame(badMagic), GarpErrorCode.PROTOCOL_ERROR);

  const badVersion = frame.slice();
  badVersion[4] = 1;
  expectCode(() => decodeGarpFrame(badVersion), GarpErrorCode.UNSUPPORTED_WIRE_VERSION);

  const badHeader = frame.slice();
  badHeader[6] = 0;
  badHeader[7] = 0x31;
  expectCode(() => decodeGarpFrame(badHeader), GarpErrorCode.INVALID_ARGUMENT);

  const badReserved = frame.slice();
  badReserved[14] = 1;
  expectCode(() => decodeGarpFrame(badReserved), GarpErrorCode.INVALID_ARGUMENT);

  const badRequestBinding = frame.slice();
  const text = new TextDecoder().decode(badRequestBinding.subarray(48));
  const changed = text.replace("00000000-0000-0000-0000-000000000002", "00000000-0000-0000-0000-000000000003");
  const bytes = textEncoder.encode(changed);
  badRequestBinding.set(bytes, 48);
  expectCode(() => decodeGarpFrame(badRequestBinding), GarpErrorCode.HEADER_JSON_MISMATCH);
}

function testDuplicateKeys() {
  const payload = "{\"garp\":\"1.24\",\"type\":\"PING\",\"request_id\":null,\"session_id\":null,\"timestamp\":\"2026-01-01T00:00:00.000Z\",\"sequence\":null,\"payload\":{},\"payload\":{}}";
  const bytes = textEncoder.encode(payload);
  const frame = new Uint8Array(48 + bytes.length);
  const view = new DataView(frame.buffer);
  frame.set([0x47, 0x41, 0x52, 0x50], 0);
  view.setUint8(4, 0);
  view.setUint8(5, 0);
  view.setUint16(6, 48, false);
  view.setUint32(8, bytes.length, false);
  view.setUint16(12, GarpMessageType.PING, false);
  view.setUint16(14, 0, false);
  frame.set(bytes, 48);
  expectCode(() => decodeGarpFrame(frame), GarpErrorCode.INVALID_ARGUMENT);
}

function testPromptOpacityAndOptions() {
  const prompt = "  A\r\nB\nC\r\nCafe\u0301  ";
  assert.equal(new TextEncoder().encode(prompt).length, 18);
  validateMessagePayload("PROMPT", {
    prompt,
    options: {
      timeout_ms: "0",
      auto_continue: false,
      max_continuations: 8,
      force_focus: false,
      simulate_enter: false,
      _extensions: {},
    },
  });
}

function testStrictSchemas() {
  expectCode(() => validateMessagePayload("OPEN_TAB", { url: "file:///tmp/a" }), GarpErrorCode.INVALID_ARGUMENT);
  expectCode(() => validateMessagePayload("PROMPT", {
    prompt: "ok",
    options: { auto_continue: "false" },
  }), GarpErrorCode.INVALID_ARGUMENT);
}

await testAuthenticationTranscript();
testPingVector();
testHeaderValidation();
testDuplicateKeys();
testPromptOpacityAndOptions();
testStrictSchemas();

console.log("GARP/1.24 conformance unit vectors: PASS");
