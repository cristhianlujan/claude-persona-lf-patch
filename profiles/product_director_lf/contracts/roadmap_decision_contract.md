# Contract — Roadmap Decision

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/product_director_lf/SKILL.md`

## Purpose
Use this contract when the product question involves prioritization, MVP boundaries, future phases or release tradeoffs.

## Required decision fields
- decision_subject
- decision_context
- selected_option
- rejected_options
- MVP_scope
- future_scope
- priority_rationale
- risk_tradeoff
- dependencies
- acceptance_criteria
- next_gate

## Rules
- The worker must choose or block; it cannot only list alternatives.
- MVP scope must be smaller than total ambition.
- Rejected options must include a reason.
- Future scope cannot be disguised as current scope.

## Blocking condition
Return `BLOCKED_PRODUCT_RISK` if the requested roadmap decision creates hidden user pressure, overpromise, misleading value, or operational debt that cannot be controlled.