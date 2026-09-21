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
16. Current provider-side generation is pinned to SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_4. V0.2 and V0.3 remain validator-readable for historical compatibility and cannot be newly generated to bypass V0.4 obligations.
17. Repair disposition is derived before solution design. Exact current evidence may close the case as `NO_REPAIR_REQUIRED` only for `ALREADY_RESOLVED` or `NOT_MATERIAL`; this disposition cannot carry a repair delta, selected alternative, implementation package, transition or rollback.
18. Every material quantitative policy decision is explicitly inventoried and grounded in existing canonical authority, a reusable evidence-backed calibration rule, or a mechanically resolvable implementation precondition whose resolution cannot change design. Incident-only timing/count samples cannot close policy.
19. Every material process/lifecycle is represented as a node graph with authority, I/O, state/transition, producer/consumer, wiring/control, failure/recovery, evidence and acceptance. A material node left `DESIGN_BLOCKING` prevents repair-spec closure.

## Required output
- `status`
- `profile_pack_id`
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
