# Contract — Frontend Prototype Missing Input Policy

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/frontend_prototype_architect_lf/SKILL.md`

## Purpose
Define when Frontend Prototype Architect must stop instead of inventing product, UI or technical decisions.

## Return `FRONTEND_MISSING_INPUT_STATE` when
- Product Direction Spec is missing.
- UI Section Spec or Production UI Spec is missing.
- Target viewport is missing.
- CTA label or route intent is missing.
- Allowed/forbidden content is unclear.
- Sandbox destination path is missing.
- Accessibility baseline cannot be determined.

## Minimum output
- missing_fields
- why_required
- risk_if_assumed
- safe_next_gate

## Rule
Request only the minimum missing information. Do not ask for data already available in Router, Supabase, GitHub sandbox runs or upstream profile outputs.