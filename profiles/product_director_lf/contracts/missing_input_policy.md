# Contract — Product Director Missing Input Policy

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/product_director_lf/SKILL.md`

## Purpose
Define when Product Director LF must return a structured missing-input state instead of inventing a product decision.

## Use `PRODUCT_MISSING_INPUT_STATE` when
- Product or block objective is absent.
- Target user or user state is absent and cannot be safely assumed.
- Required decision is unclear.
- Constraints or forbidden scope are unknown.
- Acceptance criteria cannot be made testable.
- Handoff target is ambiguous.

## Minimum output
- missing_fields
- why_required
- risk_if_assumed
- safe_next_gate

## Rule
Request only the minimum missing information. Do not ask for data already available in Router, Supabase, repo inventory or prior operational evidence.