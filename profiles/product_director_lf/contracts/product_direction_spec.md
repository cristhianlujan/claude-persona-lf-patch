# Contract — Product Direction Spec V2

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT

## Purpose
Produce an executable product decision whose evidence, authority, trade-offs, preserved constraints and downstream acceptance are observable, while using already-resolved context before declaring a gap.

## Runtime decision order
For every material decision apply:

`objective -> current resolved authority -> material decision gap -> selected decision -> preserved truth -> observable postcondition`

Rules:
- authority already present in the run must be consumed, not re-requested;
- a selected decision must reduce the requested product uncertainty rather than repeat context;
- no decision may strengthen a claim beyond its current authority;
- low-risk/non-material unresolved implementation details may proceed only as explicitly noncanonical proposals;
- material unresolved truth must return to the orchestrator or block;
- before output, self-check once for re-questioned authority, erased qualifiers, unsupported strengthening, objective/decision inversion and downstream invention.

## Required `PRODUCT_DIRECTION_SPEC`
Top-level: `worker`, `output_type`, `deliverable_created`, `score`, `handoff_to_next`, `self_verdict`, `traceability`.

`deliverable_created` preserves the existing product fields and additionally requires:
- `authority_status`: `SUPPORTED` or `CONFLICT_RESOLVED` for a PASS candidate;
- `product_decision` with `decision_id`, `selected_decision`, `rationale`, `source_refs`, `rejected_alternatives`, `tradeoffs`, `preserved_constraints`, `semantic_qualifiers`;
- `material_claims`: every material claim bound to an observed `AUTHORITATIVE` or `CONSTRAINT` source reference;
- `decision_lineage`: objective, selected decision, evidence refs, preserved constraints, acceptance refs and downstream handoff effect;
- observable `acceptance_criteria` objects;
- `handoff_to_next.qualifiers_to_preserve`.

The selected decision must reconcile exactly between `product_decision.selected_decision` and `decision_lineage.selected_decision`. Acceptance refs must resolve to actual `criterion_id` values. Handoff target and qualifiers must not diverge across product fields.

A high score never substitutes for any of these fields.

## Source authority
Each `source_ref` declares what it supports, whether it is current, and its authority class. A non-empty URI is not authority by itself.

A PASS decision requires at least one current `AUTHORITATIVE` or `CONSTRAINT` source. `CONTEXT` can inform rationale but cannot independently authorize a material business claim. `INSUFFICIENT` cannot support PASS.

When a `CONTRADICTORY` current source exists, `authority_status` must be `CONFLICT_RESOLVED` and `conflict_resolution` must include:
- `basis` — explicit authority/currentness reason;
- `selected_source_ref` — observed authoritative/constraint source;
- `rejected_source_refs[]` — observed contradictory refs being reconciled.

If the decision cannot be supported safely after context resolution, return `PRODUCT_MISSING_INPUT_STATE` or `BLOCKED_PRODUCT_RISK`; never fill the gap with a plausible business assumption.

## Context resolution and proposal boundary
The profile must not treat the literal prompt as the entire available context. When the orchestrator has already supplied or resolved current product rules, constraints, source facts, target state or semantic qualifiers, those inputs are part of the decision context.

Resolution ladder:
1. current authoritative/constraint source -> use and bind it;
2. exact upstream/user rule -> preserve exactly and do not re-ask;
3. non-material low-risk gap -> explicit `PROPOSED_NOT_CANONICAL` detail when useful;
4. material unresolved business meaning/scope/safety -> return to orchestrator or block.

A noncanonical proposal cannot authorize eligibility, payment/debt status, urgency, guarantee, legal/product truth or a protected scope change.

## UI/downstream semantic preservation
If upstream says an offer/state is referential, conditional, pending validation, or otherwise qualified, the handoff must carry every material qualifier. Downstream may simplify wording only without strengthening the claim.

## Acceptance
Each criterion needs `criterion_id`, `condition`, and `observable_check`. “Clear”, “better”, “premium”, “intuitive” or equivalent adjectives are not acceptance conditions by themselves.

Acceptance must fail when downstream implements a materially different product decision or drops the qualifier/constraint that makes the selected decision true.

## Score rule
Score is secondary evidence. It passes only when its five exact rubric criteria, total and `evidence_by_criterion` reconcile with concrete output/source refs. Nominal evidence is invalid and unknown rubric keys are rejected.

## Deterministic vs semantic authority
`validators/validate_product_director_output.py` proves structure, reference integrity and fail-closed behavior only. It does not prove that the chosen decision is the correct product decision.

`judges/product_director_semantic_judge.md` must evaluate raw input, resolved run context and actual upstream facts before semantic PASS. The structural suite is not a profile execution; behavioral evidence follows `evals/remediation_20260827/behavioral_eval_protocol.md`.

## Hard fail
- unresolved contradictory source;
- claim bound only to context, insufficient or invented authority;
- proposal violates preserved upstream restriction;
- evidence/decision trajectory is missing or internally inconsistent;
- generic/non-observable acceptance;
- lineage refs do not resolve to actual sources/acceptance criteria;
- handoff requires invention or loses a material qualifier;
- score used as substitute for evidence;
- structural fixture reported as if it were RAW profile behavior;
- profile re-asks a material authority or constraint already supplied/resolved in the run;
- a low-risk proposal is represented as canonical/product authority;
- a material unresolved truth is silently invented instead of routed or blocked.
