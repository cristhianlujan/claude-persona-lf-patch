# CARD-UPDATE-I7-IR-001 — Independent Review Handoff

## Review mode

Operate in `INDEPENDENT_CHAT_CONTEXT`.
Do not use producer conclusions, prior chats, memory, PR descriptions, expected verdicts, or previous receipts as semantic proof.
The producer receipts are artifacts under review, not authority.

## Frozen manifest

Read first:

`github://cristhianlujan/claude-persona-lf-patch@db6b98a2b118f9e76bb6a1bc6844c584ee6ecfbb/sandbox/lf_contract_gate_test/card_update_i7_independent_review_v0_1/i7_frozen_review_manifest_v0_1.json`

Review case must be exactly:

`CARD-UPDATE-I7-IR-001`

## Immutable review objects

### I4 — recorder/trust hardening
Ref: `8a4dcb9232738718fe4032971d7853495d337a9f`

Review only:
- `sandbox/lf_contract_gate_test/card_update_i4_recorder_core_v0_1/i4_operation_neutral_card_recorder_v0_1.sql`
- `sandbox/lf_contract_gate_test/card_update_i4_recorder_core_v0_1/i4_trust_null_fail_closed_patch_v0_1.sql`
- `sandbox/lf_contract_gate_test/card_update_i4_recorder_core_v0_1/i4_final_receipt_v0_1.json`

### I5 — carrier adapter intents/guards
Ref: `2b4e5a000802307fbc13597b9b33f3c8da95f454`

Review only:
- `sandbox/lf_contract_gate_test/card_update_i5_carrier_adapters_v0_1/i5_carrier_adapter_intent_v0_1.sql`
- `sandbox/lf_contract_gate_test/card_update_i5_carrier_adapters_v0_1/i5_final_receipt_v0_1.json`
- `supabase/migrations/20260913050553_lf_card_update_i5_carrier_adapter_intent_v1.sql`

### I6 — rollback/readiness
Ref: `8498bd2a5380d5bf1048233831f2137962786ce0`

Review only:
- `sandbox/lf_contract_gate_test/card_update_i6_negative_matrix_v0_1/i6_adversarial_rollback_contract_v0_1.json`
- `sandbox/lf_contract_gate_test/card_update_i6_negative_matrix_v0_1/i6_readiness_receipt_v0_1.json`

The current `main` is not a substitute for any frozen ref. A later `main` may be inspected only to verify whether a declared source-parity blocker still exists; it must not replace the reviewed objects.

## Required semantic review

Attempt to falsify, at minimum:

1. Missing/null trust must fail closed. Confirm nullable JSON comparisons cannot skip a blocker.
2. Stale provider revision must fail closed before carrier mutation.
3. Wrong carrier, document, anchor, path, or route must fail closed.
4. Caller-provided assertions, hashes, receipts, or booleans must not become operational authority merely because they are present.
5. The Card wrapper must still prevent step 90/provider dispatch under the I4/I5 no-write ceiling.
6. I5 write intent must be server-derived, bounded, deterministic/hash-bound, tamper-detecting, and have `provider_call_authorized=false`.
7. GitHub carrier handling must require an explicit durable Supabase binding; a synthetic structural test must not be misrepresented as a live bound Card positive.
8. Existing generic effect guard semantics must prevent automatic redispatch when a reservation exists without a durable success receipt.
9. Reversible baseline must contain the actual canonical pre-write content, match its SHA, revision, anchor/range and be immutable after a clean baseline step.
10. Rollback design must not overwrite concurrent provider edits: rollback requires a fresh post-write current revision guard and must manual-hold if that guard is stale.
11. Source parity must not be bypassed. If the I5 migration is applied remotely but absent from current `main`, controlled write readiness remains blocked.
12. No receipt or contract may claim real provider write, authentic post-write receipt, real rollback, production, Golden, runtime, promotion, or merge when only no-write evidence exists.

## Runtime evidence IDs allowed for read-only corroboration

You may read these exact Supabase executions only as corroboration of the frozen artifacts; do not mutate them:

- `EXEC-CARD-UPDATE-I4-PREWRITE-PASS-20260912-001`
- `EXEC-CARD-UPDATE-I4-NEG-MISSING-TRUST-20260912-001`
- `EXEC-CARD-UPDATE-I4-NEG-STALE-20260912-001`
- `EXEC-CARD-UPDATE-I4-NEG-WRONG-CARRIER-20260912-001`
- `EXEC-CARD-UPDATE-I5-ADAPTER-INTENT-20260912-001`
- `EXEC-CARD-UPDATE-I6-BASELINE-IMMUTABILITY-20260913-001`

Supabase remains the operational authority. Google Docs/GitHub carrier content may be read only for exact transport-integrity/currentness corroboration when explicitly bound; they do not decide state, rules, permissions, routing, applicability or promotion.

## Forbidden actions

Do not repair, edit, rebase, merge, promote, activate runtime, authorize production/Golden, execute carrier writes, execute rollback writes, change SHAs/refs, or replace a frozen artifact with another version.

Do not use an expected producer verdict. If evidence is contradictory, report it.

## Verdict vocabulary

Exactly one:

- `PASS_WITH_BLOCKERS_NO_WRITE`
- `FAIL_SEMANTIC_GAP`
- `BLOCKED_ARTIFACT_INTEGRITY`

A pass does **not** authorize write/merge/production. It means only that the reviewed no-write controls are semantically coherent within their evidence ceiling.

## Required final receipt

Return only one JSON object, no prose before or after it, with schema:

`LF_CARD_UPDATE_I7_INDEPENDENT_REVIEW_RECEIPT_V0_1`

Required fields:
- `schema`
- `review_case`
- `reviewer_context` = `INDEPENDENT_CHAT_CONTEXT`
- `reviewed_refs`
- `artifact_integrity`
- `falsification_results`
- `semantic_findings`
- `verdict`
- `open_blockers`
- `authorization_ceiling`

`authorization_ceiling` must remain exactly:

`NO_MERGE_NO_GOLDEN_NO_PRODUCTION_NO_RUNTIME_NO_CARRIER_WRITE`
