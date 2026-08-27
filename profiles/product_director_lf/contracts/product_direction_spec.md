# Contract — Product Direction Spec

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT

## Purpose
Produce an executable product decision whose evidence, authority, trade-offs, preserved constraints and downstream acceptance are observable.

## Required `PRODUCT_DIRECTION_SPEC`
Top-level: `worker`, `output_type`, `deliverable_created`, `score`, `handoff_to_next`, `self_verdict`, `traceability`.

`deliverable_created` preserves the existing product fields and additionally requires:
- `authority_status`: `SUPPORTED` or `CONFLICT_RESOLVED` for a PASS candidate;
- `product_decision` with `decision_id`, `selected_decision`, `rationale`, `source_refs`, `rejected_alternatives`, `tradeoffs`, `preserved_constraints`, `semantic_qualifiers`;
- `material_claims`: every material claim bound to an observed source reference;
- `decision_lineage`: objective, selected decision, evidence refs, preserved constraints, acceptance refs and downstream handoff effect;
- observable `acceptance_criteria` objects;
- `handoff_to_next.qualifiers_to_preserve`.

## Source authority
Each `source_ref` declares what it supports, whether it is current, and its authority class. `CONTRADICTORY` sources require an explicit authority/currentness-based resolution. `INSUFFICIENT` evidence cannot support PASS.

If the decision cannot be supported safely, return `PRODUCT_MISSING_INPUT_STATE` or `BLOCKED_PRODUCT_RISK`; never fill the gap with a plausible business assumption.

## UI/downstream semantic preservation
If upstream says an offer/state is referential, conditional, pending validation, or otherwise qualified, the handoff must carry that qualifier. Downstream may simplify wording only without strengthening the claim.

## Acceptance
Each criterion needs `criterion_id`, `condition`, and `observable_check`. “Clear”, “better”, “premium”, “intuitive” or equivalent adjectives are not acceptance conditions by themselves.

## Score rule
Score is secondary evidence. It passes only when its five criteria, total and `evidence_by_criterion` reconcile with concrete output/source refs. Nominal evidence is invalid.

## Hard fail
- unresolved contradictory source;
- unsupported material claim;
- proposal violates preserved upstream restriction;
- evidence/decision trajectory is missing;
- generic/non-observable acceptance;
- handoff requires invention or loses a material qualifier;
- score used as substitute for evidence.
