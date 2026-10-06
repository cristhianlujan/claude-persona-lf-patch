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


## Review hardening — orphan vs live nonterminal runs

The contract cutover does **not** mutate or invalidate any run.

A non-invalidated CURATING/VALIDATING run is classified as an orphan only when a later-created, non-invalidated COMPLETED run exists for the **same pantalla_id**. The migration reports the orphan ids and requires the set to be exactly `{22,309}`.

At the current readback:

- run 22 / pantalla 51 -> orphan because run 511 is a later non-invalidated COMPLETED run;
- run 309 / pantalla 55 -> orphan because run 493 is a later non-invalidated COMPLETED run.

Any additional orphan, disappearance/reclassification of either expected orphan, or any nonterminal run without a later COMPLETED sibling aborts for human review.

The executable SQL contains a negative self-test where a CURATING run has no later COMPLETED sibling; it must classify as **live/blocking**.

No changes are made to `input_readiness_runs`, `input_readiness_runs_invalidation_shape`, or `fn_guard_input_readiness_run()`.

## Revision-lineage chain

5.13.1 no longer overwrites the 5.13 `revision_lineage` object.

The new link stores:

- previous revision = 5.13;
- previous full `especificacion` snapshot;
- previous lineage object;
- previous contract SHA = `e2db44d0bc4aeb6f5205d95f84c3366d37cf1644b5ec69dfd3240c4c82bbf25b`.

The saved 5.13 snapshot still contains its 5.12 link with
`previous_contract_sha256=55e67871bd13b203927ed0b5978128d6462807481c1a062e2a6ac1a3092bddca`.

The postcheck reconstructs the historical contract envelope using the saved 5.13 `especificacion` and requires the reconstructed SHA to equal `e2db44d0...`.

Expected final 5.13.1 contract SHA after this exact candidate:
`dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516`.

## Exact final function MD5 postcheck

| Function | final MD5 |
|---|---|
| `fn_guard_input_family_semantic_depth_v510()` | `9c605193666ec694e0ca6a550fe7e48e` |
| `fn_guard_input_na_positive_authority_v512()` | `916176f62880f6987fb99d4703b32a2a` |
| `fn_guard_input_stage_earliest_boundary()` | `ce4ac1c826648c4a981a1dc65da216cb` |
| `fn_guard_input_validator_semantic_coherence_v512()` | `81d56655cdd96927b62aa3aef7359e35` |
| `fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)` | `9ffa930caf6c197993bd2c3f36c9f8d9` |

The migration checks these exact MD5 values; it does not use a substring/position check for final identity.

## Transaction ownership

The migration source intentionally contains no explicit `BEGIN` or `COMMIT`.

The migration train calls `lf_migration_exact_apply.py`. Its exact fallback payload wraps:

`BEGIN -> lock supabase_migrations.schema_migrations -> source SQL -> exact ledger INSERT -> COMMIT`.

Therefore the train owns the atomic transaction and ledger commit boundary. The source migration must not introduce an inner transaction boundary.

## Functions confirmed not to require 5.13.1 edits

- `fn_guard_input_family_assessment_insert()` resolves the live contract revision and compares the run/evidence values to it; it has no literal 5.13 allowlist.
- `fn_guard_input_family_assessment_update()` likewise compares the run pin and logical validator evidence to the live revision. Its only explicit revision set is the older semantic-depth compatibility branch `('5.7','5.8','5.9')`, unrelated to 5.13/5.13.1.
- `fn_input_contract_clause_v1(bigint,text,text[])` is revision-agnostic: it reads and returns the live `contract_revision`.
- `fn_input_governance_execute(integer,text)` resolves the execution contract/live run and has no literal 5.13 comparison.

These functions are intentionally untouched.
