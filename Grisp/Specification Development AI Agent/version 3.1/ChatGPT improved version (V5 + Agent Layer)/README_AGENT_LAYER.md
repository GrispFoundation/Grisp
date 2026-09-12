# GSDA/3.1 Agent Layer — continued implementation

This layer sits above `GSDA31.pas` and turns the deterministic kernel into an agent-facing API.

## Components

- `GSDA31.Agent.pas`
  - task/run lifecycle
  - typed peer input
  - round execution
  - deterministic candidate selection
  - candidate artifact creation
  - candidate freeze
  - publication call

- `GSDA31.Gateway.pas`
  - JSON command boundary suitable for GARP/Firefox integration
  - create_task
  - start_run
  - peer_message
  - freeze_candidate
  - publish
  - state

- `GSDA31.AgentDemo.dpr`
  - local end-to-end development smoke test

## Important boundary

The current kernel still contains development-level simplifications inherited from the previous implementation, especially the reliability state and human-signature validation. This agent layer does not hide those limitations.

The next implementation phase should replace the neutral 1/2 reliability prior with the exact GSDA/3.1 reliability subsystem, then add typed findings/repairs/scores/evidence and a real deterministic round scheduler.

## Firefox integration

Firefox should communicate with the gateway, not manipulate kernel state directly. The local bridge should hold the peer secret and generate the HMAC token. Browser/page JavaScript should not receive the shared secret.
