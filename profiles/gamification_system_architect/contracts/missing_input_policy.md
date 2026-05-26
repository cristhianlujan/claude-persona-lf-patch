# Missing Input Policy

## Purpose
Prevent the worker from inventing sensitive or unsafe context.

## Allowed pipeline actions
- `CONTINUE_WITH_LOW_RISK_ASSUMPTIONS`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

## Never assume
- income
- debt amount
- payment capacity
- product eligibility
- legal approval
- financial benefit
- user consent
- user emotional state beyond provided evidence

## Low-risk assumptions
Allowed only when they do not affect financial outcomes, legal meaning, user eligibility or pressure-sensitive decisions.

## Required missing-input output
Use `schemas/gamification_missing_input.schema.json` and state missing fields, why needed, safe assumptions, blocked assumptions, recommended next gate and self-verdict.

## Research basis
- Internal LF: controlled handoff and no-invention policy.
- Own repo: UI Architect missing-input policy pattern.
- External official: structured skill outputs and progressive disclosure.
- External comparable: not applicable as primary source.
- Critical/risk: financial-context sensitivity.
- Adapted into: `contracts/missing_input_policy.md`.
- Reason for location: missing-input behavior is a reusable operational contract.