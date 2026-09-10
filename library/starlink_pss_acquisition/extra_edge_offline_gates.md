# Pre-evaluation gate: added extra fault-stimulus alignment

Frozen before the phase-aware evaluation on 2026-09-10. This is an offline
scheduler/real-guard study, not actual FFT qualification or a general
asynchronous-stimulus guarantee. Retain prior v1: 7 PASS / 5 FAIL.

Fault-to-next-positive-edge lead must be strictly positive and no greater
than one half-period (2.857143 ns in the synthetic175MHz clock). A low-phase
admission may have less than a full half-period of lead. No final publication,
forward/inverse ownership release or valid-token escape may precede the
fault; current vetoes must already be asserted before the sampling edge,
and exact sticky reasons must appear on that edge.

Kind0: known-low qualification injects without crossing the next positive
edge; known-high qualification waits for the following falling edge.
Unknown clock phase is rejected. Kind1: exactly three complete positive
edges remain held, then fault injection and readiness release occur on the
following falling edge. No assertion or check delay may be changed.

Exercise two explicitly declared synthetic provider models: the original
negedge-driven provider and a posedge-registered provider. Also exercise a
fixed low-half-cycle offset to show the permitted lead is not necessarily
half a period. These are deterministic test-provider schedules, not a claim
that arbitrary asynchronous producers or simulator process orders are safe.
Retain all failures and distinguish actual vendor provenance from these
models. Original current/sticky checks, reset kinds2/3, raw217/qualified
observers, complete numerical/CSV gates and runtime RTL remain literal.
