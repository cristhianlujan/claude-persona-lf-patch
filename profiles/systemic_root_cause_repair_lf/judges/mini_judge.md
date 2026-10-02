# Mini Judge — Systemic Root Cause Repair LF

## Quality authority
The mini-judge is the canonical quality gate for this profile and is vendor-neutral. Deterministic validation proves structure/consistency only. Semantic closure requires the independent semantic judge over the exact candidate plus the run's resolved scope/authority packet.

External audit is a separate oversight lane. Missing external audit is never a blocker. If an external auditor produces a material finding, that finding may block only after it is admitted through the normal governance path.

## Sandbox B evaluation order
1. Run the canonical deterministic contract/schema validators.
2. Run `judges/systemic_root_cause_semantic_judge.md` against:
   - exact candidate + SHA;
   - hash-bound `scope_authority_packet` produced before worker execution;
   - raw/resolved run context and exact upstream authority needed by material checks.
3. Validate the semantic-result structure/coverage with `validators/validate_semantic_judge_result.py` bound to the exact pre-producer `scope_authority_packet`, candidate SHA-256, and scope-packet SHA-256. The validator must prove exact coverage of every `authorized_requirements[]`, `constraints[]`, and `forbidden_changes[]` ID; a shape-valid result that omits scope items is not a semantic PASS.
4. Only then apply any score/rubric. A score can never override a semantic hard fail.

## PASS
Return `PASS_TO_QUALITY_PACK` only when:
- deterministic output validation passes;
- semantic judge returns `PASS_INDEPENDENT_SEMANTIC`;
- semantic result validator passes;
- all seven semantic invariants pass;
- all scope requirements/material constraints have dispositions;
- all independently observed candidate changes are reconciled against both producer-declared delta and authorized scope;
- no material open design decision remains;
- no blocking condition remains.
- when material research is applicable, the digest-bound pre-research baseline and incremental-value delta have passed independent semantic review; MATERIAL_UPLIFT is independently substantiated or NO_MATERIAL_UPLIFT is accepted without forcing novelty, and UNPROVEN is absent;
- for V0.4, current repair disposition, all material quantitative decisions and any applicable material process graph pass the independent semantic checks; a valid `NO_REPAIR_REQUIRED` is accepted as a positive evidence-bound outcome rather than forced into a repair spec.

Producer assertions such as `handoff_ready=true`, `open_design_decisions=[]`, selected alternative, declared implementation delta or research URLs are inputs to review, never proof of closure.

## RETURN TO WORKER
Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` when the candidate can be repaired inside existing authority, including:
- undeclared material change;
- out-of-scope change embedded in selected repair that can be removed/reclassified as discovery;
- incomplete decision closure;
- unsupported research impact;
- material requirement/constraint omitted;
- weak or non-falsifiable repair claim.

## RETURN TO ORCHESTRATOR
Return `RETURN_TO_ORCHESTRATOR` when the candidate requires an authority/scope decision or explicit scope expansion that the worker cannot grant itself.

## BLOCK
Return `BLOCK_PIPELINE` when:
- output attempts unauthorized GitHub/Supabase/runtime/production mutation;
- evidence or authority is fabricated;
- candidate assertions are used to bypass the canonical semantic quality gate;
- a material authority/source contradiction is hidden or downgraded to force closure;
- a mandatory fail-closed control is weakened to make the gate pass.

Score never overrides a BLOCK condition.

## Experiment boundary
Sandbox B does not yet alter the profile's existing 12 omission dimensions, 8 falsification families, or producer architecture. It changes only the semantic-judge contract and its independent scope/change reconciliation.

## V0.3/V0.4 canonical quality receipt

For SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3, SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_4 and SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_5, this same mini-judge remains the single canonical quality gate. No second judge is introduced.

The independent semantic result is the semantic decision input. The final quality decision is materialized as SRCR_QUALITY_RECEIPT_V1 and is valid only when validators/validate_quality_receipt.py proves all exact bindings:

- exact candidate revision and canonical candidate digest;
- exact external evidence bundle ID and digest;
- exact semantic-result digest, semantic verdict, candidate SHA-256 and scope-packet SHA-256;
- exact required / closed / open proof-obligation sets derived by the deterministic closure floor;
- independent review boundary metadata with reviewer_is_producer=false and producer_context_available=false.

PASS_TO_QUALITY_PACK may be encoded only when:
1. V0.3 deterministic structural closure passes for the exact candidate/evidence bundle;
2. validate_semantic_judge_result.py passes for the exact semantic result while bound to the exact scope packet and candidate/scope digests;
3. the semantic verdict is PASS_INDEPENDENT_SEMANTIC;
4. the derived required proof set equals the closed proof set and the open set is empty;
5. receipt blocking codes are empty;
6. every digest/revision binding matches current supplied bytes.

A changed candidate, evidence bundle, semantic result, proof set, or scope packet invalidates the receipt. Deterministic or semantic-utility PASS without this receipt remains pre-quality only.

The profile output must never self-issue or embed the canonical quality receipt. The receipt is produced at the independent quality boundary after candidate generation.

## V0.5 premature-stop check (verification, not coaching)

Applies to every non-ready V0.5 output (`NEEDS_MORE_EVIDENCE`, `RETURN_TO_WORKER_FOR_SELF_REPAIR`) and to every `DESIGN_BLOCKING` node of `material_process_graph`.

The judge does not redesign the answer. It checks one thing: did the producer stop while accessible evidence could still close the gap?

1. For each `DESIGN_BLOCKING` uncertainty, confirm that `attempted_sources` covers the surfaces that could plausibly close it (source at exact revision, operation definitions, execution receipts, runtime readback, EKB). The deterministic floor already proves each attempt resolves in the evidence manifest and that the manifest row records the same locator; the judge checks coverage, not existence.
2. Hydrate each attempt's `evidence_id` and confirm the recorded evidence supports the declared `result` (for example, `ABSENT` requires evidence of an empty answer to that locator). If it does not, record `ATTEMPT_RESULT_NOT_SUPPORTED` and return to worker.
3. When several `DESIGN_BLOCKING` process nodes share one uncertainty, confirm that its attempts cover every one of those nodes; a generic gap covering unrelated phases is `PREMATURE_DESIGN_BLOCKING`.
4. Sample at least one accessible surface that the candidate did not list. If it closes or materially narrows the gap, record `PREMATURE_DESIGN_BLOCKING` and return `RETURN_TO_WORKER_FOR_SELF_REPAIR` naming the surface only (not the answer).
5. If a blocker is derived from the test harness or requested profile revision rather than from the audited system, record `TEST_CONTEXT_AS_BLOCKER` and return to worker.
6. If any cited reference does not exist in live authority, record `EVIDENCE_REFERENCE_NOT_FOUND`; fabricated evidence remains a BLOCK condition.

A legitimate `NEEDS_MORE_EVIDENCE` with resolved attempts and no unlisted closing surface is a valid outcome and must not be penalized. This check never raises the bar for `SYSTEMIC_REPAIR_SPEC`.

