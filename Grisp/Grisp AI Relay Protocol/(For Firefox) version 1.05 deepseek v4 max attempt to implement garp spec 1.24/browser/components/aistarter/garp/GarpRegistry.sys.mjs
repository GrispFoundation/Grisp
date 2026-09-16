// GARP/1.24 registry. See GARP/1.24 §13 and §178.

export const GARP_PROTOCOL         = "GARP/1.24";   // canonical wire name
export const GARP_SEMANTIC_VERSION = "1.24";        // Common Envelope "garp" value
export const GARP_WIRE_VERSION     = "0x00";        // semantic wire version token
export const GARP_WIRE_VERSION_BYTE = 0x00;         // binary header byte

export const GARP_FIXED_HEADER_LENGTH = 48;
export const GARP_HANDSHAKE_LIMIT     = 1048576;    // 1 MiB (§6.5, §23)
export const GARP_DEFAULT_APPLICATION_LIMIT = 16777216;

export const GarpMessageType = Object.freeze({
  HELLO:                    0x0001,
  HELLO_CHALLENGE:          0x0002,
  HELLO_AUTH:               0x0003,
  HELLO_ACK:                0x0004,
  RESPONSE:                 0x0005,
  ERROR:                    0x0006,

  CAPABILITIES:             0x0010,
  BROWSER_STATUS:           0x0011,
  LIST_TABS:                0x0012,
  OPEN_TAB:                 0x0013,
  CLOSE_TAB:                0x0014,
  SELECT_TAB:               0x0015,
  GET_CAPABILITIES:         0x0016,

  CREATE_SESSION:           0x0020,
  ATTACH_SESSION:           0x0021,
  DETACH_SESSION:           0x0022,
  CLOSE_SESSION:            0x0023,
  RESET_SESSION:            0x0024,
  GET_SESSION:              0x0025,

  PROMPT:                   0x0030,
  CANCEL_PROMPT:            0x0031,
  GET_PROMPT_STATUS:        0x0032,
  GET_RESPONSE:             0x0033,
  SUBSCRIBE_RESPONSE:       0x0034,
  CONTINUE_PROMPT:          0x0035,

  SESSION_READY:            0x0040,
  SESSION_CHANGED:          0x0041,
  NAVIGATION:               0x0042,
  NAVIGATION_DRIFT:         0x0043,
  RECOVERY_STATE:           0x0044,
  PROVIDER_CHANGED:         0x0045,

  INPUT_SUBMITTED:          0x0050,
  GENERATION_STARTED:       0x0051,
  GENERATION_DELTA:         0x0052,
  GENERATION_PROGRESS:      0x0053,
  CONTINUATION_REQUIRED:    0x0054,
  CONTINUATION_SUBMITTED:   0x0055,
  GENERATION_COMPLETED:     0x0056,
  GENERATION_FAILED:        0x0057,
  GENERATION_CANCELLED:     0x0058,

  PROVIDER_ERROR:           0x0060,
  PROVIDER_AUTH_REQUIRED:   0x0061,
  PROVIDER_RATE_LIMITED:    0x0062,
  DIAGNOSTIC:               0x0063,

  PING:                     0x0070,
  PONG:                     0x0071,

  // ext-replay-store extension
  GET_EVENTS:               0x0100,
});

const NAME_BY_ID = new Map(
  Object.entries(GarpMessageType).map(([name, id]) => [id, name])
);
const ID_BY_NAME = new Map(
  Object.entries(GarpMessageType).map(([name, id]) => [name, id])
);

export function messageTypeName(id) {
  return NAME_BY_ID.get(id) || null;
}

export function messageTypeId(name) {
  return ID_BY_NAME.get(String(name || "").toUpperCase()) || 0;
}

// Base feature set the gateway advertises. Extensions are negotiated per §15.
export const GARP_BASE_FEATURES = Object.freeze([]);
export const GARP_SUPPORTED_EXTENSIONS = Object.freeze([
  "ext-pong",
]);