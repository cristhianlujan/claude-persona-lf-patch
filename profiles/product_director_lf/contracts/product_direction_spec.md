# Contract — Product Direction Spec

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/product_director_lf/SKILL.md`

## Purpose
Product Director LF must produce a clear, executable product decision before UX/UI, Copy, Legal/Data, Tech, QA, Composer or Backlog can proceed.

## Mandatory deliverable_created format
`deliverable_created` must be a structured Product Direction Spec, not free-text advice.

Required top-level keys:
- product_decision
- included_scope
- excluded_scope
- priority
- acceptance_criteria
- dependencies
- risks
- profiles_to_activate
- blockers
- next_step
- final_verdict
- evidence_used
- open_assumptions
- success_metric_or_proxy
- handoff_to_next
- traceability

Optional but required when the decision affects scope, sequencing, handoff, risk or prioritization:
- decision_quality_requirements

## Decision quality requirements
Use this inside `deliverable_created` when a product decision could otherwise remain vague, broad or hard to hand off. Do not create a separate layer for this requirement.

`decision_quality_requirements` must define:
- `decision_specificity`: the selected product decision, rejected alternatives and reason for selection.
- `scope_boundaries`: what is included now, what is excluded and what is future scope.
- `acceptance_testability`: acceptance criteria that can be checked without interpreting intent.
- `handoff_readiness`: what the next profile can use without inventing product intent.
- `risk_and_exclusion_clarity`: risks, blockers, unsafe claims and explicit exclusions.
- `no_vague_language`: terms that must be replaced by concrete conditions, such as improve, premium, clear, intuitive, better or engaging.

## Minimum quality bar
The decision must be specific enough that the next worker can continue without inventing the product intent. Scope must include both what is included and what is intentionally excluded.

## Hard fail
The output fails if `deliverable_created` is only narrative advice, if included/excluded scope is missing, if acceptance criteria are vague, or if the next worker must invent the decision, scope, acceptance criteria or handoff.

## Blocking condition
If the profile cannot safely define product direction, it must return `PRODUCT_MISSING_INPUT_STATE` or `BLOCKED_PRODUCT_RISK`.