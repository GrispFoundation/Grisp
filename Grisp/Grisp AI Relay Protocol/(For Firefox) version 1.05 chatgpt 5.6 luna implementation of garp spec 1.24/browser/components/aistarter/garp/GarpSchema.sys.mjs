import {
  GarpConnectionScopedTypes,
  GarpSessionEventTypes,
  GarpSessionScopedCommandTypes,
  GARP_APPLICATION_LIMIT_DEFAULT,
  GARP_DEFAULT_CONTINUATION_WAIT_MS,
  GARP_HANDSHAKE_TIMEOUT_MS,
  GARP_DEFAULT_IDLE_TIMEOUT_MS,
  GARP_DEFAULT_INTERVAL_MS,
  GARP_DEFAULT_RECOVERY_DEADLINE_MS,
  GARP_DEFAULT_RESPONSE_RETENTION_MS,
  GARP_MAX_GENERATION_BUFFER_MB,
  GARP_MAX_EVENT_HISTORY_MEMORY_MB,
  GARP_MAX_OUTSTANDING_REQUESTS,
  GARP_MAX_PROMPT_SIZE,
  GARP_MAX_QUEUED_EVENTS,
  GARP_MAX_RESPONSE_SIZE,
  GARP_PROTOCOL,
  GARP_SEMANTIC_VERSION,
  GARP_WIRE_VERSION,
} from "./GarpRegistry.sys.mjs";
import { GarpError, GarpErrorCode } from "./GarpErrors.sys.mjs";
import { byteLength, durationMs, isUuid, sortedUtf8, u32, uint64, utf8ByteCompare } from "./GarpUtil.sys.mjs";

const TOP_KEYS = new Set(["garp", "type", "request_id", "session_id", "timestamp", "sequence", "payload"]);
const FEATURE_RE = /^!?[a-z0-9][a-z0-9._-]{0,127}$/;
const STRATEGY_RE = /^[a-z][a-z0-9_]{0,63}$/;
const ISO_MS_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

function invalid(message) { throw new GarpError(GarpErrorCode.INVALID_ARGUMENT, message); }
function ensureObject(value, name) { if (!value || typeof value !== "object" || Array.isArray(value)) invalid(`${name} must be an object`); }
function exactKeys(object, required, allowed = required, name = "object") {
  ensureObject(object, name);
  for (const key of required) if (!Object.prototype.hasOwnProperty.call(object, key)) throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, `${name} missing required member ${key}`);
  for (const key of Object.keys(object)) if (!allowed.includes(key)) invalid(`${name} contains unknown member ${key}`);
}
function stringBound(value, name, min, max) {
  if (typeof value !== "string") invalid(`${name} must be a string`);
  const length = byteLength(value);
  if (length < min || length > max) invalid(`${name} length is outside ${min}..${max} bytes`);
  return value;
}
function bool(value, name) { if (typeof value !== "boolean") invalid(`${name} must be boolean`); }
function arrayUnique(array, name) {
  const set = new Set(array);
  if (set.size !== array.length) invalid(`${name} contains duplicates`);
}
function validateFeatureList(features, name) {
  if (!Array.isArray(features)) invalid(`${name} must be an array`);
  const canonical = [];
  for (const feature of features) {
    if (typeof feature !== "string" || !FEATURE_RE.test(feature)) invalid(`${name} contains invalid feature name`);
    canonical.push(feature);
  }
  arrayUnique(canonical.map(v => v.startsWith("!") ? v.slice(1) : v), name);
  const sorted = sortedUtf8(canonical);
  for (let i = 0; i < canonical.length; i++) if (canonical[i] !== sorted[i]) invalid(`${name} must be UTF-8 byte sorted`);
  return canonical;
}
function validateTimestamp(value) { if (typeof value !== "string" || !ISO_MS_RE.test(value)) invalid("timestamp must be RFC3339 UTC with millisecond precision"); }
function validateIdentity(value, name) {
  if (value !== null && !isUuid(value)) invalid(`${name} must be UUID or null`);
}
function validateSequence(value, sessionScoped) {
  if (sessionScoped) { if (typeof value !== "string") invalid("sequence must be uint64-string for session events"); uint64(value, "sequence"); }
  else if (value !== null) invalid("sequence must be null for connection-scoped messages and commands");
}

function validateCapabilitiesPayload(payload) {
  exactKeys(payload, ["protocol", "wire_version", "limits", "keepalive", "providers", "extensions"], ["protocol", "wire_version", "limits", "keepalive", "providers", "extensions"], "CAPABILITIES payload");
  stringBound(payload.protocol, "protocol", 4, 16);
  if (payload.protocol !== GARP_SEMANTIC_VERSION) invalid("CAPABILITIES.protocol mismatch");
  if (payload.wire_version !== GARP_WIRE_VERSION) invalid("CAPABILITIES.wire_version mismatch");
  ensureObject(payload.limits, "limits");
  const uint32Names = ["max_payload_bytes", "max_prompt_size", "max_response_size", "max_outstanding_requests", "max_queued_events", "max_event_history_memory_mb", "max_generation_buffer_mb", "max_error_details_bytes", "max_diagnostic_details_bytes"];
  const uint64Names = ["handshake_timeout_ms", "response_retention_ms", "continuation_wait_ms", "recovery_deadline_ms"];
  for (const name of uint32Names) u32(payload.limits[name], `limits.${name}`);
  for (const name of uint64Names) durationMs(payload.limits[name], `limits.${name}`);
  if (payload.limits.handshake_timeout_ms !== "10000") invalid("CAPABILITIES.handshake_timeout_ms must advertise the enforced 10000 ms limit");
  if (payload.limits.max_payload_bytes > 0xffffffff) invalid("max_payload_bytes invalid");
  ensureObject(payload.keepalive, "keepalive");
  exactKeys(payload.keepalive, ["enabled", "idle_timeout_ms", "interval_ms"], undefined, "keepalive");
  bool(payload.keepalive.enabled, "keepalive.enabled");
  durationMs(payload.keepalive.idle_timeout_ms, "keepalive.idle_timeout_ms");
  durationMs(payload.keepalive.interval_ms, "keepalive.interval_ms");
  if (payload.keepalive.enabled) {
    if (BigInt(payload.keepalive.interval_ms) <= 0n || BigInt(payload.keepalive.idle_timeout_ms) <= 0n || BigInt(payload.keepalive.interval_ms) >= BigInt(payload.keepalive.idle_timeout_ms)) invalid("keepalive intervals are invalid");
  }
  if (!Array.isArray(payload.providers)) invalid("providers must be an array");
  const ids = [];
  for (const entry of payload.providers) {
    exactKeys(entry, ["id", "version", "state", "input_strategies", "capabilities"], undefined, "provider entry");
    stringBound(entry.id, "provider.id", 1, 64); stringBound(entry.version, "provider.version", 1, 64);
    if (!["AVAILABLE", "UNAVAILABLE", "AUTH_REQUIRED", "RATE_LIMITED", "DEGRADED"].includes(entry.state)) invalid("invalid provider state");
    if (!Array.isArray(entry.input_strategies) || entry.input_strategies.length < 1) invalid("provider.input_strategies must contain at least one strategy");
    for (const strategy of entry.input_strategies) if (typeof strategy !== "string" || !STRATEGY_RE.test(strategy) || byteLength(strategy) > 64) invalid("invalid provider input strategy");
    arrayUnique(entry.input_strategies, "provider.input_strategies");
    const sortedStrategies = sortedUtf8(entry.input_strategies); for (let i = 0; i < sortedStrategies.length; i++) if (entry.input_strategies[i] !== sortedStrategies[i]) invalid("input_strategies must be UTF-8 byte sorted");
    exactKeys(entry.capabilities, ["streaming", "cancellation", "continuation", "diagnostics"], undefined, "provider.capabilities");
    for (const key of ["streaming", "cancellation", "continuation", "diagnostics"]) bool(entry.capabilities[key], `provider.capabilities.${key}`);
    ids.push(entry.id);
  }
  const sortedIds = sortedUtf8(ids); for (let i = 0; i < sortedIds.length; i++) if (ids[i] !== sortedIds[i]) invalid("providers must be UTF-8 byte sorted");
  arrayUnique(ids, "providers");
  if (!Array.isArray(payload.extensions)) invalid("extensions must be an array");
  for (const ext of payload.extensions) { exactKeys(ext, ["name", "version"], undefined, "extension entry"); stringBound(ext.name, "extension.name", 1, 128); stringBound(ext.version, "extension.version", 1, 64); }
  const extNames = payload.extensions.map(v => v.name); const sortedExt = sortedUtf8(extNames); for (let i = 0; i < sortedExt.length; i++) if (extNames[i] !== sortedExt[i]) invalid("extensions must be UTF-8 byte sorted");
}

function validatePromptOptions(options) {
  ensureObject(options, "PROMPT.options");
  const allowed = ["timeout_ms", "auto_continue", "max_continuations", "force_focus", "simulate_enter", "_extensions"];
  exactKeys(options, [], allowed, "PROMPT.options");
  const timeout = options.timeout_ms ?? "0"; durationMs(timeout, "timeout_ms", 86400000n);
  const auto = options.auto_continue ?? false; bool(auto, "auto_continue");
  const max = options.max_continuations ?? 8; u32(max, "max_continuations"); if (max > 1024) invalid("max_continuations exceeds 1024");
  const ff = options.force_focus ?? false; bool(ff, "force_focus");
  const se = options.simulate_enter ?? false; bool(se, "simulate_enter");
  if (Object.prototype.hasOwnProperty.call(options, "_extensions")) ensureObject(options._extensions, "PROMPT.options._extensions");
}

export function validateEnvelope(json, expectedType = null, header = null) {
  ensureObject(json, "Common Envelope");
  exactKeys(json, ["garp", "type", "request_id", "session_id", "timestamp", "sequence", "payload"], [...TOP_KEYS], "Common Envelope");
  if (json.garp !== GARP_SEMANTIC_VERSION) throw new GarpError(GarpErrorCode.UNSUPPORTED_VERSION, `Unsupported semantic version: ${json.garp}`);
  if (typeof json.type !== "string" || !/^[A-Z][A-Z0-9_]{0,63}$/.test(json.type)) throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "Envelope.type is invalid");
  if (expectedType && json.type !== expectedType) throw new GarpError(GarpErrorCode.HEADER_JSON_MISMATCH, "Envelope type does not match binary header");
  validateIdentity(json.request_id, "request_id"); validateIdentity(json.session_id, "session_id"); validateTimestamp(json.timestamp);
  const sessionEvent = GarpSessionEventTypes.has(json.type); const sessionCommand = GarpSessionScopedCommandTypes.has(json.type);
  validateSequence(json.sequence, sessionEvent);
  ensureObject(json.payload, "payload");
  if (sessionEvent) { if (json.request_id !== null) throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "Session event request_id must be null"); if (json.session_id === null) throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "Session event session_id must be non-null"); }
  if (GarpConnectionScopedTypes.has(json.type)) { if (json.session_id !== null) throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "Connection-scoped message must have null session_id"); }
  if (sessionCommand && json.session_id === null) throw new GarpError(GarpErrorCode.INVALID_ENVELOPE, "Session-scoped command requires session_id");
  if (header) {
    const hRequest = header.request_id; const hSession = header.session_id;
    if ((json.request_id ?? null) !== (hRequest ?? null) || (json.session_id ?? null) !== (hSession ?? null)) throw new GarpError(GarpErrorCode.HEADER_JSON_MISMATCH, "Header/envelope UUID mismatch");
  }
  validateMessagePayload(json.type, json.payload);
  return json;
}

export function validateMessagePayload(type, payload) {
  switch (type) {
    case "HELLO":
      exactKeys(payload, ["client_name", "client_version", "versions", "wire_versions", "features", "client_nonce"], undefined, "HELLO payload");
      stringBound(payload.client_name, "client_name", 1, 64); stringBound(payload.client_version, "client_version", 1, 64);
      if (!Array.isArray(payload.versions) || payload.versions.length < 1) invalid("HELLO.versions invalid"); if (!payload.versions.includes(GARP_SEMANTIC_VERSION)) invalid("HELLO does not offer GARP/1.24");
      if (!Array.isArray(payload.wire_versions) || payload.wire_versions.length < 1) invalid("HELLO.wire_versions invalid"); if (!payload.wire_versions.includes("0x00")) throw new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, "HELLO does not offer wire version 0x00");
      validateFeatureList(payload.features, "HELLO.features");
      if (typeof payload.client_nonce !== "string") invalid("HELLO.client_nonce invalid");
      break;
    case "HELLO_CHALLENGE":
      exactKeys(payload, ["server_name", "server_version", "selected_version", "selected_wire_version", "features", "server_nonce"], undefined, "HELLO_CHALLENGE payload");
      stringBound(payload.server_name, "server_name", 1, 64); stringBound(payload.server_version, "server_version", 1, 64);
      if (payload.selected_version !== GARP_SEMANTIC_VERSION) throw new GarpError(GarpErrorCode.UNSUPPORTED_VERSION, "Unsupported selected version");
      if (payload.selected_wire_version !== "0x00") throw new GarpError(GarpErrorCode.UNSUPPORTED_WIRE_VERSION, "Unsupported selected wire version");
      validateFeatureList(payload.features, "HELLO_CHALLENGE.features"); if (typeof payload.server_nonce !== "string") invalid("HELLO_CHALLENGE.server_nonce invalid"); break;
    case "HELLO_AUTH": exactKeys(payload, ["client_proof"], undefined, "HELLO_AUTH payload"); if (typeof payload.client_proof !== "string") invalid("client_proof invalid"); break;
    case "HELLO_ACK": exactKeys(payload, ["server_proof", "selected_version", "selected_wire_version", "features"], undefined, "HELLO_ACK payload"); if (typeof payload.server_proof !== "string") invalid("server_proof invalid"); if (payload.selected_version !== GARP_SEMANTIC_VERSION || payload.selected_wire_version !== "0x00") invalid("HELLO_ACK selection invalid"); validateFeatureList(payload.features, "HELLO_ACK.features"); break;
    case "CAPABILITIES": validateCapabilitiesPayload(payload); break;
    case "BROWSER_STATUS": exactKeys(payload, ["state", "active_tab_id"], undefined, "BROWSER_STATUS payload"); if (!["STARTING", "READY", "DEGRADED", "FAILED"].includes(payload.state)) invalid("invalid browser state"); if (payload.active_tab_id !== null) stringBound(payload.active_tab_id, "active_tab_id", 1, 64); break;
    case "LIST_TABS": exactKeys(payload, [], undefined, "LIST_TABS payload"); break;
    case "OPEN_TAB": exactKeys(payload, ["url"], undefined, "OPEN_TAB payload"); stringBound(payload.url, "url", 1, 4096); { let url; try { url = new URL(payload.url); } catch (_) { invalid("OPEN_TAB.url invalid"); } if (!['http:', 'https:'].includes(url.protocol)) invalid("OPEN_TAB only permits http/https"); } break;
    case "CLOSE_TAB": case "SELECT_TAB": exactKeys(payload, ["tab_id"], undefined, `${type} payload`); stringBound(payload.tab_id, "tab_id", 1, 64); break;
    case "GET_CAPABILITIES": exactKeys(payload, [], undefined, "GET_CAPABILITIES payload"); break;
    case "CREATE_SESSION": exactKeys(payload, ["provider", "options"], ["provider", "tab_id", "options"], "CREATE_SESSION payload"); stringBound(payload.provider, "provider", 1, 64); exactKeys(payload.options, [], [], "CREATE_SESSION.options"); if (Object.prototype.hasOwnProperty.call(payload, "tab_id")) stringBound(payload.tab_id, "tab_id", 1, 64); break;
    case "ATTACH_SESSION": case "DETACH_SESSION": case "CLOSE_SESSION": case "GET_SESSION": case "RESET_SESSION": exactKeys(payload, type === "ATTACH_SESSION" || type === "RESET_SESSION" ? ["options"] : [], type === "ATTACH_SESSION" || type === "RESET_SESSION" ? ["options"] : [], `${type} payload`); if (payload.options !== undefined) exactKeys(payload.options, [], [], `${type}.options`); break;
    case "PROMPT": exactKeys(payload, ["prompt", "options"], undefined, "PROMPT payload"); if (typeof payload.prompt !== "string") invalid("PROMPT.prompt must be string"); if (byteLength(payload.prompt) > GARP_MAX_PROMPT_SIZE) invalid("prompt exceeds max_prompt_size"); validatePromptOptions(payload.options); break;
    case "CANCEL_PROMPT": case "GET_PROMPT_STATUS": case "GET_RESPONSE": case "SUBSCRIBE_RESPONSE": case "CONTINUE_PROMPT": exactKeys(payload, ["prompt_request_id"], undefined, `${type} payload`); if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id must be UUID"); break;
    case "PING": exactKeys(payload, [], undefined, "PING payload"); break;
    case "RESPONSE": ensureObject(payload, "RESPONSE payload"); if (typeof payload.success !== "boolean") invalid("RESPONSE.success must be boolean"); break;
    case "ERROR": ensureObject(payload, "ERROR payload"); exactKeys(payload, ["code", "message"], ["code", "message", "details"], "ERROR payload"); stringBound(payload.code, "error.code", 1, 64); stringBound(payload.message, "error.message", 0, 1024); if (payload.details !== undefined) { ensureObject(payload.details, "ERROR.details"); if (byteLength(JSON.stringify(payload.details)) > GARP_MAX_ERROR_DETAILS_BYTES) invalid("ERROR.details too large"); } break;
    case "SESSION_READY": exactKeys(payload, ["provider", "tab_id", "url", "page_generation"], undefined, type); stringBound(payload.provider, "provider", 1, 64); stringBound(payload.tab_id, "tab_id", 1, 64); stringBound(payload.url, "url", 1, 4096); uint64(payload.page_generation, "page_generation"); break;
    case "SESSION_CHANGED": exactKeys(payload, ["changed", "page_generation"], undefined, type); if (!Array.isArray(payload.changed) || payload.changed.length < 1 || payload.changed.length > 4) invalid("changed invalid"); arrayUnique(payload.changed, "changed"); for (const v of payload.changed) if (!["provider", "tab_id", "url", "page_generation"].includes(v)) invalid("invalid changed member"); uint64(payload.page_generation, "page_generation"); break;
    case "NAVIGATION": exactKeys(payload, ["page_generation", "url"], undefined, type); uint64(payload.page_generation, "page_generation"); stringBound(payload.url, "url", 1, 4096); break;
    case "NAVIGATION_DRIFT": exactKeys(payload, ["page_generation", "reason"], undefined, type); uint64(payload.page_generation, "page_generation"); if (!["UNEXPECTED_URL", "DOCUMENT_REPLACED", "PROVIDER_CONTEXT_LOST", "ACTOR_CONTEXT_STALE"].includes(payload.reason)) invalid("invalid navigation drift reason"); break;
    case "RECOVERY_STATE": exactKeys(payload, ["state", "reason", "deadline_remaining_ms"], undefined, type); if (!["RECOVERING", "RECOVERED", "FAILED"].includes(payload.state)) invalid("invalid recovery state"); if (!["ACTOR_REPLACED", "DOCUMENT_REPLACED", "UNEXPECTED_URL", "PROVIDER_CONTEXT_LOST", "CANCELLATION_UNVERIFIED", "PROVIDER_RECOVERY", "INTERNAL_DESYNC"].includes(payload.reason)) invalid("invalid recovery reason"); durationMs(payload.deadline_remaining_ms, "deadline_remaining_ms"); break;
    case "PROVIDER_CHANGED": exactKeys(payload, ["previous_provider", "provider", "page_generation"], undefined, type); if (payload.previous_provider !== null) stringBound(payload.previous_provider, "previous_provider", 1, 64); stringBound(payload.provider, "provider", 1, 64); uint64(payload.page_generation, "page_generation"); break;
    case "INPUT_SUBMITTED": exactKeys(payload, ["prompt_request_id", "page_generation", "strategy"], undefined, type); if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid"); uint64(payload.page_generation, "page_generation"); stringBound(payload.strategy, "strategy", 1, 64); if (!STRATEGY_RE.test(payload.strategy)) invalid("strategy invalid"); break;
    case "GENERATION_STARTED": exactKeys(payload, ["prompt_request_id", "message_id", "revision", "page_generation"], undefined, type); if (!isUuid(payload.prompt_request_id) || !isUuid(payload.message_id)) invalid("generation ids invalid"); if (uint64(payload.revision, "revision") !== 0n) invalid("GENERATION_STARTED revision must be 0"); uint64(payload.page_generation, "page_generation"); break;
    case "GENERATION_DELTA": exactKeys(payload, ["prompt_request_id", "message_id", "revision", "delta", "mode", "page_generation"], undefined, type); if (!isUuid(payload.prompt_request_id) || !isUuid(payload.message_id)) invalid("generation ids invalid"); uint64(payload.revision, "revision"); if (payload.delta === undefined || typeof payload.delta !== "string") invalid("delta invalid"); if (!["APPEND", "REPLACE"].includes(payload.mode)) invalid("mode invalid"); uint64(payload.page_generation, "page_generation"); break;
    case "GENERATION_PROGRESS": exactKeys(payload, ["prompt_request_id", "message_count", "page_generation"], undefined, type); if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid"); u32(payload.message_count, "message_count"); uint64(payload.page_generation, "page_generation"); break;
    case "CONTINUATION_REQUIRED": exactKeys(payload, ["prompt_request_id", "continuation_count", "max_continuations", "page_generation"], undefined, type); if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid"); u32(payload.continuation_count, "continuation_count"); u32(payload.max_continuations, "max_continuations"); uint64(payload.page_generation, "page_generation"); break;
    case "CONTINUATION_SUBMITTED": exactKeys(payload, ["prompt_request_id", "page_generation", "continuation_count", "strategy"], undefined, type); if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid"); uint64(payload.page_generation, "page_generation"); u32(payload.continuation_count, "continuation_count"); stringBound(payload.strategy, "strategy", 1, 64); break;
    case "GENERATION_COMPLETED": validateGenerationTerminalPayload(payload, false); break;
    case "GENERATION_FAILED": validateGenerationTerminalPayload(payload, true); break;
    case "GENERATION_CANCELLED": validateCancelledPayload(payload); break;
    case "PROVIDER_ERROR": exactKeys(payload, ["provider", "code", "message", "retryable", "prompt_request_id", "page_generation"], undefined, type); stringBound(payload.provider, "provider", 1, 64); stringBound(payload.code, "code", 1, 64); stringBound(payload.message, "message", 0, 1024); bool(payload.retryable, "retryable"); if (payload.prompt_request_id !== null && !isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid"); uint64(payload.page_generation, "page_generation"); break;
    case "PROVIDER_AUTH_REQUIRED": exactKeys(payload, ["provider", "reason", "page_generation"], undefined, type); stringBound(payload.provider, "provider", 1, 64); stringBound(payload.reason, "reason", 1, 64); uint64(payload.page_generation, "page_generation"); break;
    case "PROVIDER_RATE_LIMITED": exactKeys(payload, ["provider", "retry_after_ms", "page_generation"], undefined, type); stringBound(payload.provider, "provider", 1, 64); durationMs(payload.retry_after_ms, "retry_after_ms"); uint64(payload.page_generation, "page_generation"); break;
    case "DIAGNOSTIC": exactKeys(payload, ["level", "stage", "code", "message", "details", "actor_instance"], undefined, type); if (!["TRACE", "DEBUG", "INFO", "WARN", "ERROR"].includes(payload.level)) invalid("diagnostic level invalid"); if (!["TRANSPORT", "AUTHENTICATION", "SESSION", "SUBMISSION", "GENERATION", "CONTINUATION", "CANCELLATION", "RECOVERY", "PROVIDER"].includes(payload.stage)) invalid("diagnostic stage invalid"); stringBound(payload.code, "diagnostic.code", 1, 64); stringBound(payload.message, "diagnostic.message", 0, 1024); ensureObject(payload.details, "diagnostic.details"); if (byteLength(JSON.stringify(payload.details)) > GARP_MAX_DIAGNOSTIC_DETAILS_BYTES) invalid("diagnostic details too large"); stringBound(payload.actor_instance, "diagnostic.actor_instance", 1, 64); break;
    case "GET_EVENTS": exactKeys(payload, ["from_sequence", "max_events"], undefined, type); if (uint64(payload.from_sequence, "from_sequence") < 1n) invalid("from_sequence must be >= 1"); u32(payload.max_events, "max_events"); if (payload.max_events < 1 || payload.max_events > 4096) invalid("max_events out of range"); break;
    case "PONG": exactKeys(payload, [], undefined, "PONG payload"); break;
    default: break;
  }
}

function validateGenerationTerminalPayload(payload, failed) {
  if (Array.isArray(payload.messages)) {
    const allowed = ["prompt_request_id", "error", "partial", "messages", "page_generation"];
    exactKeys(payload, failed ? ["prompt_request_id", "error", "partial", "messages", "page_generation"] : ["prompt_request_id", "messages", "page_generation"], allowed, failed ? "GENERATION_FAILED payload" : "GENERATION_COMPLETED payload");
    if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid");
    if (failed) validateErrorObject(payload.error);
    if (failed !== undefined && typeof payload.partial === "boolean" === false && failed) invalid("partial invalid");
    if (!Array.isArray(payload.messages)) invalid("messages must be array");
    for (const message of payload.messages) { exactKeys(message, ["message_id", "revision", "response"], undefined, "message result"); if (!isUuid(message.message_id)) invalid("message_id invalid"); uint64(message.revision, "revision"); if (typeof message.response !== "string") invalid("message.response invalid"); }
    uint64(payload.page_generation, "page_generation"); return;
  }
  if (failed) {
    exactKeys(payload, ["prompt_request_id", "error", "partial", "response", "page_generation"], undefined, "GENERATION_FAILED payload");
    if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid"); validateErrorObject(payload.error); bool(payload.partial, "partial"); if (payload.response !== null && typeof payload.response !== "string") invalid("response invalid"); uint64(payload.page_generation, "page_generation"); if (payload.response === null && payload.partial) invalid("partial cannot be true without response content");
  } else {
    exactKeys(payload, ["prompt_request_id", "message_id", "revision", "response", "page_generation"], undefined, "GENERATION_COMPLETED payload");
    if (!isUuid(payload.prompt_request_id) || !isUuid(payload.message_id)) invalid("generation ids invalid"); uint64(payload.revision, "revision"); if (typeof payload.response !== "string") invalid("response invalid"); uint64(payload.page_generation, "page_generation");
  }
}
function validateCancelledPayload(payload) {
  if (Array.isArray(payload.messages)) {
    exactKeys(payload, ["prompt_request_id", "cancel_verified", "partial", "messages", "page_generation"], undefined, "GENERATION_CANCELLED payload");
    if (!isUuid(payload.prompt_request_id)) invalid("prompt_request_id invalid"); bool(payload.cancel_verified, "cancel_verified"); if (!payload.cancel_verified) invalid("cancel_verified must be true"); bool(payload.partial, "partial"); for (const msg of payload.messages) { exactKeys(msg, ["message_id", "revision", "response"], undefined, "cancelled message"); if (!isUuid(msg.message_id)) invalid("message_id invalid"); uint64(msg.revision, "revision"); if (typeof msg.response !== "string") invalid("message response invalid"); } uint64(payload.page_generation, "page_generation"); return;
  }
  exactKeys(payload, ["prompt_request_id", "message_id", "revision", "cancel_verified", "partial", "response", "page_generation"], undefined, "GENERATION_CANCELLED payload");
  if (!isUuid(payload.prompt_request_id) || !isUuid(payload.message_id)) invalid("generation ids invalid"); uint64(payload.revision, "revision"); bool(payload.cancel_verified, "cancel_verified"); if (!payload.cancel_verified) invalid("cancel_verified must be true"); bool(payload.partial, "partial"); if (typeof payload.response !== "string") invalid("response invalid"); uint64(payload.page_generation, "page_generation");
}
function validateErrorObject(error) { ensureObject(error, "error"); exactKeys(error, ["code", "message"], undefined, "error"); stringBound(error.code, "error.code", 1, 64); stringBound(error.message, "error.message", 0, 1024); }

export function capabilitiesObject(providerRegistry) {
  const providers = providerRegistry.list().sort((a, b) => utf8ByteCompare(a.id, b.id));
  for (const provider of providers) provider.input_strategies = sortedUtf8(provider.input_strategies);
  return {
    protocol: GARP_SEMANTIC_VERSION,
    wire_version: GARP_WIRE_VERSION,
    limits: {
      handshake_timeout_ms: String(GARP_HANDSHAKE_TIMEOUT_MS),
      max_payload_bytes: GARP_APPLICATION_LIMIT_DEFAULT,
      max_prompt_size: GARP_MAX_PROMPT_SIZE,
      max_response_size: GARP_MAX_RESPONSE_SIZE,
      max_outstanding_requests: GARP_MAX_OUTSTANDING_REQUESTS,
      max_queued_events: GARP_MAX_QUEUED_EVENTS,
      max_event_history_memory_mb: GARP_MAX_EVENT_HISTORY_MEMORY_MB,
      max_generation_buffer_mb: GARP_MAX_GENERATION_BUFFER_MB,
      response_retention_ms: String(GARP_DEFAULT_RESPONSE_RETENTION_MS),
      continuation_wait_ms: String(GARP_DEFAULT_CONTINUATION_WAIT_MS),
      recovery_deadline_ms: String(GARP_DEFAULT_RECOVERY_DEADLINE_MS),
      max_error_details_bytes: GARP_MAX_ERROR_DETAILS_BYTES,
      max_diagnostic_details_bytes: GARP_MAX_DIAGNOSTIC_DETAILS_BYTES,
    },
    keepalive: {
      enabled: true,
      idle_timeout_ms: String(GARP_DEFAULT_IDLE_TIMEOUT_MS),
      interval_ms: String(GARP_DEFAULT_INTERVAL_MS),
    },
    providers,
    extensions: [
      { name: "ext-pong", version: "1.0" },
      { name: "ext-replay-store", version: "1.0" },
    ],
  };
}

export { GARP_DEFAULT_CONTINUATION_WAIT_MS, GARP_DEFAULT_RECOVERY_DEADLINE_MS };
