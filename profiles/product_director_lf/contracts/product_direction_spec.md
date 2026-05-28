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

## Minimum quality bar
The decision must be specific enough that the next worker can continue without inventing the product intent. Scope must include both what is included and what is intentionally excluded.

## Blocking condition
If the profile cannot safely define product direction, it must return `PRODUCT_MISSING_INPUT_STATE` or `BLOCKED_PRODUCT_RISK`.