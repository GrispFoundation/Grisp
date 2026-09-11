# GRISP v1 Firefox gateway

The Firefox source is isolated from the Delphi core. `garp/` implements the
binary GARP/1.0 frame and correlated session/request state; `providers/` is the
provider-adapter boundary. Provider adapters must emit explicit readiness,
authentication, rate-limit, generation, and continuation states. They must not
normalize prompts or artifact content.
