# CONTRACT-5.13.1 — prerequisite for R5-D / R5-E

Status: **DRAFT / NOT AUTHORIZED TO APPLY**

## Intent

Revision 5.13.1 changes only the representation contract for Validator evidence:

- `assertions` remains required on the **logical rehydrated evidence**.
- Physical storage may be either inline `assertions` or `assertion_set_sha256`.
- `fn_input_validator_evidence_rehydrate_v1(jsonb)` is the canonical logical projection.
- `validator_sha256` is always defined over that logical projection.
- `STORAGE_COMPACTION` is a semantically neutral representation transform, never a validator receipt change.

## Atomicity / five functions

The same migration that bumps 5.13 -> 5.13.1 contains complete static definitions for all five live functions with literal 5.13:

1. `fn_guard_input_family_semantic_depth_v510()` — base MD5 `34368d67fbc7c1cf234a7be0c76f1d76`.
2. `fn_guard_input_na_positive_authority_v512()` — base MD5 `4db6bd12af2ece03171627cd14e310f9`.
3. `fn_guard_input_stage_earliest_boundary()` — base MD5 `150b5acf8fb918ff37d81fd1ce6705dc`.
4. `fn_guard_input_validator_semantic_coherence_v512()` — **post-R5-C** base MD5 `5f47ef6f1e0a8d5ee8ccd830ef9ba297`.
5. `fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)` — base MD5 `4921a8d69a47e037212edaae7738475e`.

No runtime patching is used.

## Nonterminal-run gate

Allowed run statuses are CURATING / VALIDATING / COMPLETED / BLOCKED. The migration aborts unless there are **zero non-invalidated CURATING or VALIDATING runs**.

At design time the live blockers are:

- run 22 — CURATING;
- run 309 — CURATING.

Therefore this candidate is intentionally **not currently applicable**.

## Existing 5.13 runs and stale-pin avoidance

Existing rows keep their recorded `contract_revision=5.13` and their historical `contract_snapshot_sha256`. They are not rewritten.

The zero-nonterminal preflight is what prevents `INPUT_READINESS_CONTRACT_PIN_STALE_DURING_VALIDATION`: the contract SHA is changed only after every old 5.13 run has left CURATING/VALIDATING. New runs created after cutover pin revision 5.13.1 and the new contract SHA.

All five touched functions continue accepting 5.13 and additionally accept 5.13.1. Thus historical terminal 5.13 evidence remains interpretable. R5-E representation-only compaction of terminal receipts is already guarded by R5-C before the validator-currentness path and does not rewrite the historical contract pin.

## Review / authorization

This unit touches Cristhian-owned contract/runtime functions. **Explicit Cristhian OK is required before leaving Draft or receiving ready-to-merge.** Claude review is also required.

No R5-D or R5-E apply is authorized by this PR.
