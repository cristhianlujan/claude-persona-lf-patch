# Causal Lane Exclusivity Contract — LF Learning Engine

## Purpose

Prevent two materializing lanes from advancing the same causal chain at the same time while preserving parallel read-only research and review.

This is a central Motor governance control. It is not owned by an individual learning case such as AUD-018, and it does not replace ACT-0001, Supabase, S30, S28, or a domain specialist.

## Authority and storage

- Operational authority: Supabase.
- Durable carrier: existing `public.lf_operation_execution.manifest`.
- Do not create a parallel ownership database/table for this control.
- GitHub files define the technical contract/validator only; GitHub is not the operational ownership authority.
- Google Drive is never an ownership authority.

## Canonical exclusion key

For every materializing lane compute exactly one key:

`causal_lane_key = UPPER(TRIM(EKB_code)) + "|" + UPPER(TRIM(target_asset)) + "|" + UPPER(TRIM(primary_gate))`

Permanent invariant:

`1 causal chain = 1 active writer`

PR invariant:

`1 PR = 1 lane + 1 owner + 1 primary gate`

## Roles

### WRITER

Only the active writer may:

- mutate the canonical candidate for the lane;
- advance `next_gate` / frontier;
- modify Router bindings for the lane;
- change canonical lifecycle state;
- close or mutate the causal EKB state;
- emit a closure receipt for the lane.

A writer must hold a fresh Supabase ownership claim before any materializing write.

### REVIEWER_READ_ONLY

Parallel reviewers are allowed for:

- research;
- read-only audit;
- adversarial review;
- semantic review;
- evidence verification on frozen artifacts.

A reviewer never receives write authority from this contract. `write_intent=true` for a reviewer must fail closed with `BLOCK_REVIEWER_WRITE_FORBIDDEN`.

## Fresh-main/currentness gate

Before a new writer is authorized:

1. read current `main` from the exact GitHub ref;
2. bind both `base_main_sha` and `current_main_sha`;
3. require equality and a 40-hex SHA;
4. record `currentness_source = GITHUB_PUBLIC_API_EXACT_REF_V1`;
5. when continuing after a closed predecessor on the same key, invalidate stale/currentness receipts from the predecessor before the new claim.

Mismatch or absent currentness returns `BLOCK_FRESH_MAIN_CURRENTNESS_REQUIRED`.

A closed predecessor whose old receipts were not invalidated returns `BLOCK_STALE_RECEIPTS_NOT_INVALIDATED`.

## Supabase claim gate

A writer may proceed only after a fresh Supabase readback confirms all of:

- `authority = SUPABASE`;
- `result = OWNERSHIP_ACQUIRED` or `OWNERSHIP_REUSED_IDEMPOTENT`;
- exact `causal_lane_key`;
- exact `owner`;
- exact `execution_id`;
- `active = true`.

Missing or mismatched claim returns `BLOCK_SUPABASE_CLAIM_REQUIRED` or `BLOCK_SUPABASE_CLAIM_MISMATCH`.

The acquisition transaction must serialize on the causal key before checking/updating ownership. The current implementation reuses PostgreSQL transaction advisory locking and the existing `lf_operation_execution.manifest`; it does not require a new ownership table.

## Conflict behavior

If another active `WRITER` exists for the same key:

- return `BLOCK_CAUSAL_LANE_ALREADY_OWNED`;
- set the newcomer to `WAITING_UPSTREAM`;
- identify the current owner/execution in evidence;
- do not copy, absorb, rebase from, or advance the current owner's candidate.

Same key + same owner + same execution is idempotent reuse, not a second writer.

A different `primary_gate` produces a different causal key and may proceed independently when its own ownership/currentness gates pass.

## Release and successor

The current owner remains active until its lane is explicitly closed/superseded and the Supabase claim is marked inactive. A successor must then perform a fresh-main/currentness check, invalidate stale receipts, acquire its own claim, and only then continue.

## Deterministic validator

Use:

`validators/validate_causal_lane_exclusivity.py`

The validator checks lane cardinality, owner/gate identity, reviewer restrictions, active-writer conflicts, fresh-main/currentness, predecessor receipt invalidation, and Supabase claim readback.

Its deterministic self-test matrix is:

`evals/causal_lane_exclusivity_matrix.json`

A validator PASS proves contract mechanics only. It does not prove a real Supabase claim unless the claim is independently read back from Supabase in the current run.
