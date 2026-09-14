export const GARP_PROTOCOL = "GARP/1.01";
export const GARP_VERSION_BYTE = 0x11; // major=1, minor=1
export const GARP_FIXED_HEADER_LENGTH = 48;
export const GARP_MAX_FRAME_SIZE = 16 * 1024 * 1024;

export const GarpMessageType = Object.freeze({
  HELLO: 0x0001,
  HELLO_ACK: 0x0002,
  CAPABILITIES: 0x0003,
  BROWSER_STATUS: 0x0004,
  HELLO_CHALLENGE: 0x0005,
  RESPONSE: 0x0006,
  HELLO_AUTH: 0x0007,

  LIST_TABS: 0x0010,
  OPEN_TAB: 0x0011,
  CLOSE_TAB: 0x0012,
  SELECT_TAB: 0x0013,

  CREATE_SESSION: 0x0020,
  ATTACH_SESSION: 0x0021,
  DETACH_SESSION: 0x0022,
  CLOSE_SESSION: 0x0023,
  RESET_SESSION: 0x0024,

  PROMPT: 0x0030,
  PROMPT_ACK: 0x0031,
  CANCEL_PROMPT: 0x0032,
  CANCEL_ACK: 0x0033,
  GET_PROMPT_STATUS: 0x0034,
  GET_RESPONSE: 0x0035,
  SUBSCRIBE_RESPONSE: 0x0036,

  SESSION_READY: 0x0040,
  SESSION_CHANGED: 0x0041,
  INPUT_SUBMITTED: 0x0042,
  GENERATION_STARTED: 0x0043,
  GENERATION_DELTA: 0x0044,
  GENERATION_PROGRESS: 0x0045,
  CONTINUATION_REQUIRED: 0x0046,
  CONTINUATION_SUBMITTED: 0x0047,
  GENERATION_COMPLETED: 0x0048,
  GENERATION_FAILED: 0x0049,

  NAVIGATION: 0x0050,
  PROVIDER_ERROR: 0x0051,
  AUTH_REQUIRED: 0x0052,
  RATE_LIMITED: 0x0053,
  DIAGNOSTIC: 0x0054,

  PING: 0x0060,
  PONG: 0x0061,

  ERROR: 0x00f0,
});

const TYPE_NAME_BY_ID = new Map(
  Object.entries(GarpMessageType).map(([name, id]) => [
    id,
    name.toLowerCase(),
  ])
);

const TYPE_ID_BY_NAME = new Map(
  Object.entries(GarpMessageType).map(([name, id]) => [
    name.toLowerCase(),
    id,
  ])
);

export function messageTypeName(id) {
  return TYPE_NAME_BY_ID.get(id) || null;
}

export function messageTypeId(name) {
  return (
    TYPE_ID_BY_NAME.get(String(name || "").toLowerCase()) || 0
  );
}

export const GarpFeature = Object.freeze([
  "streaming",
  "cancel",
  "sessions",
  "stable_tabs",
  "response_events",
  "page_generation",
  "diagnostics",
]);