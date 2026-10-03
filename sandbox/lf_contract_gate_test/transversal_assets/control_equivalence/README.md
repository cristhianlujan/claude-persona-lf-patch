# CONTROL_EQUIVALENCE_JUDGE — candidate contract v1

Owner: `SUPER_ADMIN` (D-V2.2 / event 19472).

This source is the T-EQUIV candidate for `IG_CURATOR_VALIDATOR_REFACTOR_V2`. It is a pure comparison/judgment component, not an executor. It consumes already-produced current/candidate JSON results from one frozen subject/snapshot and an explicit consumer policy. It never mutates Input Governance readiness, never promotes a candidate, and is not a global PASE gate.

## Reuse / prior art

The repository already contains the bounded `lf_contract_check_parity_equivalence_v1.py` judge for one Contract Check control. T-EQUIV preserves its fail-closed principles (same frozen inputs, exact evidence, no execution ownership) while adding the field-by-field classification required by the IG plan. It does not modify or replace that S28/Contract Check-specific judge.

## D0–D5 boundary

Only two level semantics are authoritative at this point:

- `D0`: exact field equality; emitted automatically when there are zero divergences.
- `D4`: false-PASS risk; always blocking. A policy that declares `D4` as non-blocking is rejected.

`D1`, `D2`, `D3` and `D5` are accepted labels but have **no global meaning in T-EQUIV**. Their exact meaning and field mapping must be declared by the consumer policy. An observed changed field with no exact mapping fails closed as `BLOCKED_UNCLASSIFIED_DIVERGENCE`. This prevents T-EQUIV from inventing the still-pending IG divergence semantics.

## Intended IG consumers already declared by the plan

- `M3.9 / PAULO-135`: old engine vs new resolvers shadow.
- `M4.10 / PAULO-137`: new oracle vs current Validator.
- `M7.8 / PAULO-054`: cached vs non-cached parity.
- `M9.3 / PAULO-090`: vNext vs 5.13 non-decisional shadow.
- `M9.5 / PAULO-091`: consumer-owned D0–D5 field policy; engine moved to T-EQUIV.

Outside IG, `LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1 / PASE-ATOM-F05-011` requires an `Equivalent replay`, but this document does **not** claim that PASE is already bound to T-EQUIV. Cross-plan binding remains separate authority work.

## Negative contract

The deterministic test proves four cases without runtime or DB mutation:

1. exact equality => `D0 / PASS_EQUIVALENT`;
2. seeded `story_ready_status: BLOCKED -> READY` mapped by the fixture to `D4` => blocking divergence;
3. changed field without consumer mapping => fail closed;
4. `D4` configured as non-blocking => fail closed.

The D4 fixture is specifically a false-PASS-risk example and does not define D1/D2/D3/D5 semantics for IG.
