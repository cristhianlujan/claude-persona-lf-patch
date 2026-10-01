# WAIVER_AUTHORITY_V1

## Purpose

`SADM-PP-L3-018` creates the canonical POST-PASE waiver authority that is currently missing.

It does **not** reinterpret `VALIDATION_EXEMPTION_ONE_USE` or `private.lf_event_validation_exemptions` as closure waivers. Those assets provide reusable mechanism patterns only.

Flow:

`caller -> ORCHESTRATOR_EXECUTION_GUARD -> WAIVER_AUTHORITY -> plan/currentness -> exact approved grant -> atomic one-use consume -> LF_WAIVER_AUTHORITY_RECEIPT_V1`

## Boundary

`WAIVER_AUTHORITY` emits only `WAIVER_AUTHORIZED` or `WAIVER_BLOCKED`. It never emits `WAIVED` and never closes POST-PASE. The future `CLOSURE_GATE` owns closure vocabulary and may consume a valid waiver receipt as one input.

## Reused mechanisms, not reused authority

FAST_LOOKUP_MAP (`inventory.fn_lookup_v2`) found no canonical `WAIVER_AUTHORITY`.

`VALIDATION_EXEMPTION_ONE_USE` proves reusable mechanisms: immutable exact-scope hash, external approval binding, expiry <= 1 hour, `max_uses=1`, atomic consumption and replay rejection. Its event-validation table/functions remain semantically separate.

## Exact waiver identity

Every waiver is cross-bound to `post_pase_execution_id`, `control_id`, `plan_digest`, `merge_sha`, `source_revision`, `subject_ref` and `request_digest`.

## Approval

Grant issuance requires a separate `POST_PASE_WAIVER_APPROVED` governance event with schema `post-pase-waiver-governance/v1`, decision `APPROVED`, authority `LF_GOVERNANCE`, and the exact grant digest. The waiver request cannot authorize itself.

## Anti-replay

Authorization is produced **after** atomic consumption, not before it. The candidate dedicated store `private.lf_post_pase_waivers` enforces max one use, active/unexpired exact scope, atomic `uses_count 0 -> 1`, and binding to `consumed_by_execution_id` + `consumed_by_request_digest`.

A repeated consume cannot succeed.

## Currentness

The typed receipt also requires:
- `PLAN_AUTHORITY_DRIFT_GUARD` with `MATCH` or `AUTHORIZED_DELTA` bound to the same `plan_digest`;
- `CURRENTNESS_AUTHORITY` with `CURRENT` or `CURRENT_REBOUND` bound to the same `source_revision`.

## Tests

`test_waiver_authority_v1.py` covers 12 checks: positive exact consumed waiver; missing orchestrator entry; plan mismatch; stale currentness; scope mismatch; event-validation exemption masquerading as waiver authority; already-consumed grant; replay; request-digest mismatch; missing consumption; legacy exemption schema rejection; and authority-ref cross-bind mismatch.

Expected: `PASS_WAIVER_AUTHORITY_V1 checks=12`.

## Materialization state

Source-only candidate. `WAIVER_AUTHORITY_source_projection_v1.sql` is intentionally blocked until `LF_GOVERNANCE`, `CAPABILITY_EXECUTION_CONTRACT`, `PLAN_AUTHORITY_DRIFT_GUARD`, `CURRENTNESS_AUTHORITY` and `AUTHORITY_READBACK` exist live.

No Supabase apply, cutover, runtime, deploy or production activation is authorized by this unit.
