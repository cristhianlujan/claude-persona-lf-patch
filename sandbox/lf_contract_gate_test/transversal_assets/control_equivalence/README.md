# CONTROL_EQUIVALENCE_JUDGE v1

Owner: `SUPER_ADMIN`.

`CONTROL_EQUIVALENCE_JUDGE` is a transversal, read-only comparison capability. It consumes already-produced current/candidate JSON for the same frozen subject plus an explicit consumer policy. It never executes either side, mutates authoritative state, approves a change, or promotes a candidate.

## Global semantics

Only semantics that are genuinely transversal live in the provider:

- `D0`: exact equality; zero divergent fields.
- `D4`: known false-PASS risk; always blocking. A consumer policy that marks D4 non-blocking is invalid.

`D1`, `D2`, `D3` and `D5` are labels available to consumers but have no global business meaning. Their meaning and exact field mappings are consumer-owned policy. An observed changed field with no mapping fails closed as `BLOCKED_UNCLASSIFIED_DIVERGENCE`.

This separation is intentional: the transversal judge owns comparison mechanics and fail-closed invariants; consumers own the domain meaning of non-global divergence classes.

## Contract

Input:

- `current`: current/baseline JSON for one frozen subject;
- `candidate`: candidate JSON for the same subject;
- consumer policy `lf-control-equivalence-policy/v1` containing:
  - `consumer_ref`;
  - exact `field_levels` mapping for any admitted non-D0 divergence.

Output:

- `PASS_EQUIVALENT` / `D0` when exactly equal;
- `DIVERGENCE_CLASSIFIED` when all changed fields are mapped and non-blocking;
- `BLOCKED_DIVERGENCE` when any mapped divergence is blocking;
- `BLOCKED_UNCLASSIFIED_DIVERGENCE` when any changed field lacks exact consumer mapping;
- `BLOCKED` for malformed policy or an invalid attempt to make D4 non-blocking.

All outputs are non-decisional with respect to execution and have `authoritative_mutation=false`.

## Consumers proven in T-EQUIV

### IG — M7.8 cached/non-cached parity

M7.8 uses an **exact-only policy**: `field_levels={}`. Therefore exact equality is D0/PASS and every difference is `BLOCKED_UNCLASSIFIED_DIVERGENCE`. T-EQUIV does not decide whether a cached/non-cached difference is harmless; M7.8 must reconcile it until the outputs are identical except for any explicitly governed consumer exception added later.

### Non-IG fixture — OPS configuration equivalence

A separate non-IG fixture proves the same provider can compare generic configuration payloads with a consumer-declared D2 meaning, without provider code branches or IG terminology.

## Existing prior art

The bounded Contract Check parity-equivalence implementation remains prior art for its own control. T-EQUIV does not replace `MIGRATION_SOURCE_PARITY`, does not become a PASE global gate, and does not duplicate currentness, evidence, or runtime-verification authorities.

## Intended IG consumers

- `M3.9 / PAULO-135`
- `M4.10 / PAULO-137`
- `M7.8 / PAULO-054`
- `M9.3 / PAULO-090`
- `M9.5 / PAULO-091`

Each consumer must declare its own field policy. No consumer may reinterpret an unmapped divergence as PASS.

## Negative contract

The deterministic test proves:

1. exact equality => `D0 / PASS_EQUIVALENT`;
2. seeded false-PASS (`story_ready_status: BLOCKED -> READY`) mapped D4 => blocking;
3. unmapped changed field => fail closed;
4. D4 configured non-blocking => fail closed;
5. M7.8 exact-only policy: any cached/non-cached difference blocks;
6. a non-IG configuration consumer can use a consumer-owned D2 meaning without provider changes.

## Governance

- Capability code: `CONTROL_EQUIVALENCE_JUDGE`.
- Version: `1.0.0`.
- Owner: `SUPER_ADMIN`.
- Registry/current authority: `public.lf_capability_registry` + `public.lf_capability_current`.
- Guarded binding: `public.fn_lf_capability_bind_from_orchestrator_v1`.
- No runtime/production activation is performed by this capability.
