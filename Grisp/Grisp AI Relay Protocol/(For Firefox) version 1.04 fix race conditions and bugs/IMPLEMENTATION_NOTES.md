# GARP/1.01 implementation notes

This task targets the GARP/1.01 contract developed in the accompanying conversation.

The following wire-level values are frozen by this implementation because the source protocol text provided to the implementation task did not include a final numeric registry section:

* protocol string: `GARP/1.01`
* version byte: `0x11`
* fixed frame header: 48 bytes
* UUID fields: raw RFC 4122 16-byte representation
* all frame integers: big-endian
* message registry includes HELLO_CHALLENGE and generic RESPONSE for command results
* authentication: HMAC-SHA256 challenge/response

If the user's separate GARP/1.01 document assigns different numeric values or wire encodings, the implementation MUST be aligned to that document before claiming conformance. No semantic GRISP assumptions are encoded in the Firefox gateway.

The provider selectors were intentionally derived from the existing Firefox AI Automation implementation supplied for this task. They are expected to require maintenance as provider DOMs change.
