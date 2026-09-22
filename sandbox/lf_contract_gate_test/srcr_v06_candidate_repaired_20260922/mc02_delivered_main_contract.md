# Main Contract — Systemic Root Cause Repair LF

## Contract
Produce a structured, evidence-grounded systemic repair specification for recurrent or architecturally material failures.

## Required semantic conditions
1. `symptom`, `immediate_cause`, and `systemic_root_cause` are distinct.
2. `causal_chain` links observed failure to the first bad control and escape control.
3. `systemic_root_cause` explains recurrence, not just the latest occurrence.
4. Exact current authority is resolved from live execution evidence, not only declared source/code.
5. Every material declared-vs-live contradiction is represented in `authority_contradictions` as a blocking finding until reconciled.
6. `should_exist_assessment` identifies real consumers, impact of removal, and a native/already-existing alternative before preserving or adding a component.
7. When ambiguity is material, at least three materially distinct alternatives are compared.
8. The selected alternative includes explicit tradeoffs and falsification results, including undeclared/unversioned caller when authority is material.
9. The selected repair is the minimum sufficient origin repair that removes the failure class.
10. `invariant` and `hard_guard` are testable and fail closed.
11. Acceptance includes historical recurrence regressions and current-case proof.
12. Residual risks and unresolved authority are explicit and do not absorb known contradictions.
13. Final acceptance requires the canonical evidence-bound semantic quality gate on the exact candidate revision. External audit is optional and cannot block merely because it has not run.
14. Evidence-class vocabularies are namespaced by field: recurrence provenance and falsification execution state are distinct contracts and may not borrow each other's enum values.
15. When material research is required, incremental value must be measured against a digest-bound pre-research solution baseline. The producer may report MATERIAL_UPLIFT or NO_MATERIAL_UPLIFT, but semantic materiality is accepted only by the independent quality boundary; UNPROVEN cannot close a ready material-research specification.
16. Current provider-side generation is pinned to SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6. V0.2 through V0.5 remain validator-readable for historical compatibility and cannot be newly generated to bypass V0.6 obligations.
17. Repair disposition is derived before solution design. Every disposition carries an executable `repair_disposition.verification` with an explicit method, expected result and evidence references so the current disposition can be independently re-checked. Exact current evidence may close the case as `NO_REPAIR_REQUIRED` only for `ALREADY_RESOLVED` or `NOT_MATERIAL`; this disposition cannot carry a repair delta, selected alternative, implementation package, transition or rollback and does not require repair-only ceremony such as fabricated recurrence, alternative comparison or a systemic causal chain when those are immaterial to proving current disposition. Non-ready cases may use repair_disposition=UNDETERMINED when currentness/materiality itself remains design-blocking.
18. Every material quantitative policy decision is explicitly inventoried and grounded in existing canonical authority, a reusable evidence-backed calibration rule, or a mechanically resolvable implementation precondition whose resolution cannot change design. Incident-only timing/count samples cannot close policy.
19. Every material process/lifecycle is represented as a node graph with authority, I/O, state/transition, producer/consumer, wiring/control, failure/recovery, evidence and acceptance. V0.6 requires explicit material edges and evidence-bound AS-IS closure: producer, transport, actual consumer, canonical route/authority when applicable, enforcement, effect/readback and terminality. `next_gate` must resolve to a real consumer. Post-transition currentness, identity consistency and rollback executability are explicit applicability/status proofs. Proposed wiring never closes an observed AS-IS edge. A material node or edge left `DESIGN_BLOCKING` prevents repair-spec closure.

## Required output
- `status`
- `profile_pack_id`
- `case_mode`
- `repair_disposition`
- `quantitative_decisions`
- `material_process_graph`
- `symptom`
- `immediate_cause`
- `systemic_root_cause`
- `causal_chain`
- `first_bad_control`
- `escape_control`
- `recurrence_evidence`
- `authority_contradictions`
- `repair_level`
- `should_exist_assessment`
- `alternatives`
- `selected_alternative`
- `rejected_alternatives`
- `falsification_results`
- `origin_asset`
- `origin_operation`
- `owner`
- `invariant`
- `hard_guard`
- `acceptance_criteria`
- `historical_regressions`
- `residual_risks`
- `evidence_map`
- `blocking_codes`
- `next_gate`

## Invalid output
Prose-only diagnosis, first-plausible-fix output, local repair presented as systemic without recurrence explanation, self-certification used to bypass the canonical semantic gate, unsupported authority, hidden or residualized declared-vs-live contradiction, missing `¿DEBE EXISTIR?` analysis, missing falsification, a hard guard that cannot be tested, a repair invented for a currently-resolved/non-material condition, a material numeric policy justified only by the triggering incident, or nominal lifecycle coverage that does not close each material subprocess.

## V0.3 evidence-bound semantic closure

For SYSTEMIC_REPAIR_SPEC under V0.3, closure is derived, not asserted.

- solution_depth and material omission findings generate proof obligations.
- Every required proof obligation must be represented and closed before handoff readiness can be true.
- An authority used as current must be typed EXISTING_AUTHORITY and resolve to a current evidence-manifest entry bound to the evaluated candidate/evidence bundle.
- PROPOSED_DELIVERABLE is future design and cannot satisfy existing-authority requirements.
- Material wiring requires an implementable edge: producer, data/contract, consumer, enforcement point, failure behavior and physical existing/proposed binding.
- Material state/recovery or migration/transition requires executable transition and recovery semantics; non-material cases must not be forced into those structures.
- runtime_validate.py and runtime_semantic_utility.py are deterministic pre-quality floors only.
- Accepted quality requires the canonical mini-judge receipt for the exact candidate revision/digest and evidence-bundle digest.
- A changed candidate or evidence bundle invalidates any prior quality receipt.
- Evidence manifests are resolved outside model output; the model references evidence IDs but is not the root of trust for them.
- No V0.3 rule may depend on PROFILE_RELEASE, event 14701, a specific LF table, or another case keyword.

## V0.4 transversal closure additions

V0.4 keeps the V0.3 evidence-bound closure and adds three generic obligations without case/domain keywords:
- current repair disposition before solution design;
- material quantitative-policy grounding;
- material process/lifecycle graph completeness.

The deterministic floor validates structure and explicit contradictions. The independent semantic judge remains the authority for whether currentness is sufficient, a calibration basis is genuinely reusable, and the material process graph is complete for the exact case.

## V0.5 producer-depth additions

V0.5 keeps V0.4 transversal closure and changes producer behavior without adding a second engine:
- `ARCHITECTURE_AUDIT` relaxes recurrence evidence and incident-chain length only; systemic causality and the immediate/root/first-bad/escape control claims remain required for a ready specification.
- A `DESIGN_BLOCKING` uncertainty is legitimate only when its `attempted_sources` resolve against the externally assembled evidence manifest; a blocked material-process node must reference that design-blocking uncertainty.
- An accessible but uninspected authority is unfinished investigation, not a valid reason to stop.


## V0.6 physical edge closure additions

V0.6 preserves V0.5 investigation-depth requirements and closes the distinction between component existence and actual wiring.

- Every material graph with `applies=true` has explicit `edges`.
- `REUSE_AS_IS` is allowed only for an `OBSERVED_CLOSED` edge with current external evidence for producer, transported contract/data, real consumer, enforcement and effect/readback.
- An emitted `next_gate` must resolve to a current consumer on the observed path; a label alone is not wiring.
- Canonical-route consistency, post-transition currentness, terminality, identity consistency and rollback executability are typed proof objects with explicit applicability.
- An observed failure may be paired with an `IMPLEMENTABLE` future repair, but future wiring cannot be cited as evidence that the current edge is closed.
- Deterministic validation owns these structural invariants. Semantic utility consumes the deterministic gate and does not re-implement the same structural rules.


## V0.6 control ownership

Deterministic validation exclusively owns structural blocking codes. The pre-quality semantic utility runs only after the deterministic contract gate passes and MUST NOT re-emit those structural codes. It may add only distinct utility checks. The independent semantic judge remains a separate final semantic authority and cannot be replaced by either deterministic layer.


## V0.6 pre-freeze schema discipline

The producer must validate the complete candidate against the exact current `schemas/output.schema.json` before candidate freeze/digest. A schema-invalid draft is not a frozen candidate. Typed test protocols must preserve the declared collection types for setup, action and assertions. Downstream schema validation remains an independent fail-closed control; it is not the first place an avoidable producer shape error should be discovered.


## Mandatory self-repair closure contract

The normative self-repair closure contract is `profiles/systemic_root_cause_repair_lf/contracts/mandatory_self_repair_closure.v1.json`.

For any SRCR self-maintenance that touches research execution, context transport, evidence resolution/transport, deterministic rules, finding aggregation, independent semantic review, quality receipts, physical wiring/terminality, or implementation-footprint closure:

1. all applicable MC-01..MC-13 obligations are mandatory;
2. only READBACK_CLOSED counts as closed;
3. overall closure is the logical AND of all mandatory obligations;
4. no deterministic/utility/CI PASS or producer assertion can override an open obligation;
5. exact negative and positive evidence required by each obligation must be bound to the exact profile revision under review;
6. the profile update cannot be represented as ready for governed update while any obligation remains below READBACK_CLOSED.

- MC-13 complete replay MUST be clean: zero open observations, zero failed applicable steps and zero unresolved mandatory inputs. NOT_APPLICABLE requires explicit evidence/rationale and cannot hide an applicable check.


## Mandatory per-run progress table

The mandatory self-repair closure report is part of the execution contract, not optional presentation. Every run MUST render MC-01..MC-13 as separate rows with `Punto obligatorio | Avance | Estado actual | Qué falta para 100%`, sourced from exact current readback. A run is reporting-incomplete if this table is absent, rows are grouped/omitted, or percentages are not supported by the current progress evidence.
