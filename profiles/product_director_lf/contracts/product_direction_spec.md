# Contract — Product Direction Spec

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT

## Purpose
Produce an executable product decision whose evidence, authority, trade-offs, preserved constraints and downstream acceptance are observable.

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

## Source authority
Each `source_ref` declares what it supports, whether it is current, and its authority class. A non-empty URI is not authority by itself.

A PASS decision requires at least one current `AUTHORITATIVE` or `CONSTRAINT` source. `CONTEXT` can inform rationale but cannot independently authorize a material business claim. `INSUFFICIENT` cannot support PASS.

When a `CONTRADICTORY` current source exists, `authority_status` must be `CONFLICT_RESOLVED` and `conflict_resolution` must include:
- `basis` — explicit authority/currentness reason;
- `selected_source_ref` — observed authoritative/constraint source;
- `rejected_source_refs[]` — observed contradictory refs being reconciled.

If the decision cannot be supported safely, return `PRODUCT_MISSING_INPUT_STATE` or `BLOCKED_PRODUCT_RISK`; never fill the gap with a plausible business assumption.

## UI/downstream semantic preservation
If upstream says an offer/state is referential, conditional, pending validation, or otherwise qualified, the handoff must carry every material qualifier. Downstream may simplify wording only without strengthening the claim.

## Acceptance
Each criterion needs `criterion_id`, `condition`, and `observable_check`. “Clear”, “better”, “premium”, “intuitive” or equivalent adjectives are not acceptance conditions by themselves.

## Score rule
Score is secondary evidence. It passes only when its five exact rubric criteria, total and `evidence_by_criterion` reconcile with concrete output/source refs. Nominal evidence is invalid and unknown rubric keys are rejected.

## Deterministic vs semantic authority
`validators/validate_product_director_output.py` proves structure, reference integrity and fail-closed behavior only. It does not prove that the chosen decision is the correct product decision.

`judges/product_director_semantic_judge.md` must evaluate raw input and actual upstream facts before a behavioral PASS claim. The structural suite is not a profile execution; behavioral evidence follows `evals/remediation_20260827/behavioral_eval_protocol.md`.

## Hard fail
- unresolved contradictory source;
- claim bound only to context, insufficient or invented authority;
- proposal violates preserved upstream restriction;
- evidence/decision trajectory is missing or internally inconsistent;
- generic/non-observable acceptance;
- lineage refs do not resolve to actual sources/acceptance criteria;
- handoff requires invention or loses a material qualifier;
- score used as substitute for evidence;
- structural fixture reported as if it were RAW profile behavior.
