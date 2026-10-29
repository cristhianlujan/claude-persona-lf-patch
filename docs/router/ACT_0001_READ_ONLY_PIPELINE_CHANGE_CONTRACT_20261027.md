# ACT-0001 — Change contract: read-only first, governed effects later

**Status: IMPLEMENTATION_BLOCKED — contract review required; not deployed.**

## Evidence from currently deployed functions

- `lf_router_pipeline_begin_v1(text)` always reserves a row in `lf_operation_execution`, records `request_intake`, then updates the manifest.
- `lf_router_pipeline_stage1_submit_v1(text,jsonb)` expects an existing persisted `execution_id` and records `stage1_seal`.
- `lf_router_pipeline_stage2_continue_v1(text)` reads the recorded Stage 1 and persists Stage 2.
- `lf_router_pipeline_resolve_next_transition_v1(text)` reads the recorded Stage 2 and persists the transition.
- `lf_router_pipeline_profile_semantic_prepare_v1(text)` reads the persisted transition and Stage 2.

Consequently, **removing only the initial INSERT/UPDATE breaks every downstream function**. Fixing read-only access by GRANTing write-capable SECURITY DEFINER functions is unsafe.

## Required semantics for a single dynamic pipeline

1. Initial request: immutable literal, no Supabase INSERT/UPDATE. Return a transient, non-authoritative trace of the input, Stage 1, Stage 2 and the deterministic next transition; preserve their exact existing contracts.
2. Stage 1: validate `LF_ROUTER_STAGE1_V2` and bind it to the exact literal. Stage 2 must consume this validated output, not arbitrary caller stage inputs.
3. Transition: reuse `lf_router_route_transition_resolve_v1`, do not choose a next step freely in the assistant.
4. For read-only profile investigation, use only authorized read-only controls. Do not equate semantic-selection data with an authorization or signed handoff.
5. At the first actual write/effect boundary, initiate the **existing** governed operation, bind the transient derivation/decision to its authorization, preserve anti-replay and evidence, then execute. Do not allow caller-controlled fake execution IDs or fall back silently to the legacy write path.
6. Never persist every query merely for trace display. Preserve detailed DB audit only for governed operations and explicitly required security/audit cases.

## Compatibility and prohibition

- Do not introduce another Router or independent entrypoint that duplicates Stage 1/2.
- Do not replace the existing single-argument function without migrating its callers and the persisted step consumers.
- Do not grant `supabase_read_only_user` execute rights on write-capable security-definer functions.
- Do not deploy the Gate 2 extension before this contract is resolved and fully replay-tested.
- No change to existing production functions, permissions, records or tables in this contract.

## Mandatory regression

Run `ACT_0001_REGRESION_E2E_LOGIN_B2B_CANONICA_20261027.md` verbatim from entry to the first actual governed effect; compare read-only responses and all authorized transitions to baseline, with inputs/outputs at every step. FAIL/NO_VERIFICADO if any stage is omitted or the trace is simulated.
