# Work Protocol Manifest V1 candidate

Purpose: close the gap between protocol definition, construction/execution, and independently verified progress without introducing a parallel authority.

## Candidate surfaces

- `gobernanza/contratos/work_protocol_manifest_v1.md`: semantic contract and invariants.
- `gobernanza/contratos/work_protocol_manifest_v1.schema.json`: machine-readable shape.
- `gobernanza/judges/validate_work_protocol_manifest_v1.py`: deterministic reconciliation and progress derivation.
- `test_work_protocol_manifest_v1.py`: positive and adversarial self-tests.
- `sandbox/lf_contract_gate_test/work_protocol_manifest_v1/candidate_work_protocol_manifest_v1.sql`: canonical deployable SQL candidate isolated from `supabase/migrations`. G12 must materialize these exact bytes in its own migration-only PR before any governed apply.

## Adoption model

V1 is opt-in. It does not change `fn_lf_operation_reserve_execution_v1` and does not change any operation registry row. A later governed rollout may bind selected operations after compatibility tests.

## Expected proof sequence

1. Validator self-tests PASS.
2. SQL source static checks PASS.
3. Transactional live rehearsal on LF Supabase Sandbox creates candidate functions/view, exercises positive and negative cases, then ROLLBACK.
4. Post-rollback readback proves zero residue.
5. Two domain fixtures prove reuse: Strategy execution and SRCR/profile execution.
6. Only after these proofs is a real migration/PR candidate materialized.


## Verification status

Evidence date: 2026-09-22.

### G00 Owner-first Entry — READBACK_CLOSED

- Ownership is now mandatory before authority resolution or manifest freeze through top-level `work_owner`.
- Required fields: `owner_id`, `owner_type`, `declaration_ref`, exact `declaration_sha256=request_sha256`, and `change_mode=SUPERSEDE_NEW_EXECUTION`.
- Owner identity is part of the immutable manifest. It cannot be inferred later from a branch, PR author, lease owner, blocker owner or prior execution.
- An owner change cannot happen in place; it requires a newly authorized execution/supersession.
- JSON Schema and deterministic validator reject missing owner, mismatched owner/request binding and in-place reassignment.
- Current migration exact bytes were applied inside a live Supabase transaction and rolled back. Negative probes confirmed missing/mismatched ownership fails first with `LF_WORK_PROTOCOL_OWNER_BINDING_INVALID`.
- Post-rollback readback: 0 candidate Work Protocol functions and 0 candidate controller columns persisted.
- Current migration Git blob SHA after G00: `eaa0aae1bd97314de22265323edd71ef79933537`.
- `Validate LF Packs` passed on the G00 code line. `lf-contract-check` remains separately blocked by the pre-existing missing candidate receipt; that is not an owner-gate failure.

### G03 Gate Contract — READBACK_CLOSED

- Gate types are now canonical and frozen: `ENTRY | STEP | EXIT | CLOSURE`.
- Each required obligation carries a canonical `gate_contract_sha256` derived from the live step contract + active judge binding.
- The gate projection includes preconditions, deterministic checks, judge binding/result values, required evidence, `deterministic_before_judge=true`, `fail_closed=true`, and normalized PASS/FAIL/BLOCKED mapping.
- Deterministic result must exist before judgment. A non-PASS deterministic result cannot be overridden by a judge.
- A judge result with sequence <= deterministic sequence is rejected.
- Missing gate packet, stale gate digest, missing evidence or non-canonical judge result fail closed.
- Recorded future gates that do not exist yet remain `IN_PROGRESS`; missing future steps are not incorrectly counted as blocking failures.
- Strategy begin wrapper now binds the automatically created `init_execution` step to its gate contract and readbacks the normalized gate PASS before returning.
- Derived progress view counts a step only when the canonical checklist and the gate evaluator both pass.
- Cross-domain transactional rehearsal against `EJECUCION_ESTRATEGIA_LF` and `EJECUCION_PERFIL_LF`: PASS on current migration blob.
- Strategy status-view transactional rehearsal: PASS. Positive gate produced partial `IN_PROGRESS`; mutated judge ordering produced `BLOCKED`.
- Current migration blob SHA: `5aede2b4296a4c1661791a3f8e7a18fb14a59aec`.
- Post-rollback residue: 0 gate functions / 0 test execution residue.
- Deterministic validator and source harness include positive/negative gate ordering, missing packet, digest mismatch and canonical return normalization.
- No runtime/production activation performed.
- GitHub CI / candidate receipt remain a later exact-head gate and are not claimed by G03.

### G04 Evidence / Independent Verification — READBACK_CLOSED

- Every counted gate now requires `LF_WORK_PROTOCOL_EVIDENCE_V1` exact evidence: execution, step, gate digest, actor, reproduction locator/specification, specification digest, input digest, result digest/count, source revision and observation timestamp.
- Evidence is execution-bound and freshness-bound. V1 allows a stricter per-execution window but never more than 24 hours; future timestamps beyond bounded clock skew fail closed.
- Independent verification mode is no longer producer-selectable. `verifier_mode` is an additive canonical field on `lf_operation_step_judge_bindings`; Work Protocol adoption fails closed while it is unset, and the frozen manifest must match it exactly.
- `INDEPENDENT_READBACK`, `SEMANTIC_JUDGE`, `COMPOSITE` and `CLOSURE` require a `VERIFIED` receipt from the existing append-only `private.lf_evidence_ledger_v1`; no parallel evidence table is created.
- The ledger receipt is bound to the same execution, gate, authority reference, result digest, reproduction-spec digest and source revision. The receipt actor must be a distinct completed verifier execution targeted to the producer execution.
- Existing provider-bound resolver trust is reused from `private.lf_evidence_resolver_registry_v1`; provider readback and digest recomputation must both be proven.
- Replay from another execution, producer-authored independent evidence, stale evidence, missing receipts, digest mismatch and ledger mutation are rejected.
- The derived progress view counts a recorded step only when exact evidence validation and G03 gate validation both PASS.
- Strategy begin now attaches and immediately readbacks exact deterministic evidence for its automatically recorded `init_execution` gate.
- Transactional Supabase rehearsal: PASS for deterministic Strategy evidence plus independent Strategy readback backed by the existing append-only ledger.
- Append-only mutation probe: PASS; direct UPDATE of the rehearsal ledger receipt was rejected by `BLOCK_LF_EVIDENCE_LEDGER_APPEND_ONLY`.
- Post-rollback residue: 0 verifier-mode column, 0 candidate evidence function, 0 rehearsal executions, 0 rehearsal ledger rows.
- Deterministic/source harness after G04 hardening: PASS, 58/58 checks.
- G04 changes do not activate runtime/production and do not populate verifier modes in live authority; population belongs to a later governed adoption/rollout gate.

### G06 Change / Waiver / Irreversibility — READBACK_CLOSED

- Scope change is not an in-place manifest edit. A changed scope requires a new execution that binds the exact predecessor execution, predecessor persisted manifest digest, previous/new scope digests and a new authorization digest.
- V1 uses `FULL_REQUIRED` revalidation and forbids carrying verified progress into the successor. The predecessor is derived as `SUPERSEDED_SCOPE_CHANGE` once the valid successor exists.
- Required obligations cannot be waived. Only optional obligations whose canonical step authority has `waiver_allowed=true` may be waived.
- Every waiver carries reason, residual risk, human authorization identity/reference/digest and expiry. V1 waiver TTL is at most one hour; the authority readback must independently verify the human authorization.
- Canonical step authority now includes `waiver_allowed`, `irreversible_effect` and `human_approval_required`. Work Protocol adoption fails closed while any adopted step leaves them unset.
- `irreversible_effect=true` requires `human_approval_required=true`, an exact pre-frozen approval binding and a runtime human-approval readback. Execution evidence must carry the same `irreversible_action_sha256`.
- A mismatched action digest, missing human readback or expired approval derives `BLOCKED_CONTROL`; no gate progress is counted.
- No parallel waiver/control table was introduced. Frozen control provenance remains in the manifest/checkpoint channel and existing execution/evidence authorities remain canonical.
- Transactional Supabase rehearsal: PASS. It created a governed predecessor Strategy execution, superseded it with a newly authorized expanded-scope execution, proved predecessor `SUPERSEDED_SCOPE_CHANGE`, proved successor `IN_PROGRESS`, validated an exact irreversible human approval, rejected an action-digest mutation, accepted an authorized optional waiver, and rejected a required-obligation waiver.
- Rehearsal migration blob SHA: `c059e96a58db53ef2b165721844cff3d813bc256`.
- Post-rollback residue: 0 control columns, 0 candidate control functions and 0 rehearsal executions.
- Deterministic/source harness after G06 hardening: PASS, 75/75 checks.
- No runtime/production activation and no live population of the new canonical control fields were performed; population belongs to governed rollout/adoption.

### G07 Execution Controller — READBACK_CLOSED

- G07 turns sequencing into an executable controller over the existing canonical operation primitives. No new scheduler/control table is introduced.
- Canonical step authority now carries `depends_on_step_ids`, `closure_unit_id`, `controller_order`, `execution_effect` and `parallel_safe`.
- The frozen manifest requires `dependency_mode=CANONICAL_DAG`, material WIP exactly 1, lease-backed activation, fenced checkpoints, predecessor fail-closed behavior and resume from canonical state.
- DAG validation rejects unknown dependencies, self-dependencies, duplicate controller order and cycles.
- The controller derives the next frontier from persisted execution steps. A recorded but non-verified predecessor blocks its dependents; an absent predecessor leaves them waiting.
- Read-only parallelism is allowed only for `parallel_safe=true` steps inside the same closure unit. Non-read-only work is limited to one material step.
- `lf_work_protocol_controller_activate_v1` requires the existing execution lease and exact `lease_fence`, then persists the active closure unit, active step set and plan digest through `fn_lf_operation_checkpoint_v1`.
- Step INSERT/UPDATE on Work Protocol executions is guarded. Outside the governed bootstrap of the first init step, a step write must match the active controller checkpoint and current plan.
- Restart/recovery is deterministic: after lease handoff the stale checkpoint is rejected, the planner recomputes the same frontier from canonical state, and a new fenced activation resumes it.
- Supabase transactional rehearsal: PASS. It proved init → router frontier, rejection before activation, rejection of a non-frontier step, successful fenced router activation/write/readback, dependency advance to `strategy_resolve`, WIP bypass rejection, lease-fence rollover, stale-checkpoint rejection, and successful reactivation from canonical state.
- Negative controller probes also rejected a DAG cycle and `parallel_safe=true` on a mutating step.
- Rehearsal migration blob SHA: `cf0c65ef29fac365b0c4f110933eedf5c7352648`.
- Post-rollback residue: 0 controller columns, 0 controller functions and 0 rehearsal execution rows.

### G08 Closure Controller — READBACK_CLOSED

- G08 closes the execution-discipline gap left after G07: a verified step is not enough to advance; its closure unit must first become terminal through an append-only receipt.
- Terminal local states are `CLOSED_WITH_EVIDENCE` and `BLOCKED_WITH_EVIDENCE`. A blocked closure creates explicit closure debt and never counts as verified completion.
- The next closure unit is not released while an earlier unit is `READY_TO_CLOSE`, `READY_TO_BLOCK_WITH_EVIDENCE`, `REOPEN_REQUIRED` or otherwise nonterminal.
- A blocked unit remains selectable for repair. Later dependent work still remains constrained by the G07 DAG.
- Blocker closure receipts are bound to the exact failed execution-step evidence digest; a fabricated or unrelated blocker digest is rejected.
- Closure receipts reuse `private.lf_evidence_ledger_v1`; no parallel closure/debt table was created.
- Receipts are chained through `previous_unit_receipt_sha256`. Current-state selection prefers a receipt whose subject digest matches the current unit digest, avoiding ambiguous same-transaction timestamps.
- If step/evidence state changes after closure, the previous receipt becomes stale and the unit moves to `REOPEN_REQUIRED`. A new append-only receipt is required before later units can advance.
- Global close is fail-closed unless every close-required unit is `CLOSED_WITH_EVIDENCE`, closure debt is zero and no reopen obligation remains.
- Validator adversarials pass for: close-before-next, sequential close, blocked-with-evidence debt, unit digest mutation reopening, broken receipt chain reopening downstream, and zero-debt global close.
- Live Supabase rehearsal was deliberately split after a monolithic rehearsal hit a PostgreSQL deadlock. The smaller current-blob path passed: init receipt → router failure → rejection of wrong blocker digest → `BLOCKED_WITH_EVIDENCE` → explicit debt=1 → repair → `REOPEN_REQUIRED` → next-unit blocked → reclose → debt=0 → next unit released.
- G08 split-rehearsal evidence is bound to migration blob `d634083bcaab1662af090f7bd7399c5f2e552636`. G00 subsequently changed the manifest-entry guard, so a fresh exact-head G08 behavioral replay remains required before claiming whole-branch exact-head closure.
- Transactional rollback readback for the successful split rehearsal: 0 rehearsal execution rows and 0 rehearsal evidence-ledger receipts.
- No runtime or production activation was performed.

### G09 Gate Self-Test / Cold Replay — READBACK_CLOSED

- G09 is mechanically wired into `Validate LF Packs`; it is no longer a manual/local-only check.
- The frozen matrix covers every protocol gate from G00 through G08 across five required dimensions: `positive`, `negative`, `drift`, `bypass` and `timeout`.
- Coverage is exact: 9 gates × 5 dimensions = 45 mandatory matrix cells. Missing gates, missing dimensions or unknown probe references fail closed.
- Each cold replay starts a fresh Python process. Two independent replays use different `PYTHONHASHSEED` values (11 and 97) and must emit byte-equivalent canonical JSON.
- Current cold-replay SHA-256: `1e686da403b303a9f2f955465e384fa3bbaf01c1f12f3f266e9f075bf5700a07`.
- Matrix SHA-256: `8a60022942ef27f4af18f8a006db1ad37c2bea3c387e068cb8f674c68d3a20bf`.
- All 45 gate/dimension cells PASS. The underlying validator self-test suite also passes 56/56 cases.
- G09 caught two real integration defects during construction: scope-supersession had not rebound the new owner declaration to the new request, and one G05 drift oracle expected the wrong canonical error code. Both were repaired before closure.
- `Validate LF Packs` run 11414 passed with the G09 step executed.
- `lf-contract-check` remains independently blocked by the candidate-receipt requirement; that belongs to G11 and is not counted as a G09 failure.
- No runtime or production activation was performed.

### Adaptive timeout recovery

- Timeout condition remains separate from gate verdicts and is carried by `checkpoint_payload.work_protocol_recovery`.
- Verified progress survives recovery.
- CHUNKABLE recovery must reduce work-unit size.
- CHECKPOINTABLE recovery resumes from a checkpoint.
- Exhausted recovery budget derives `BLOCKED_OPERATIONAL_TIMEOUT`, not semantic FAIL.

