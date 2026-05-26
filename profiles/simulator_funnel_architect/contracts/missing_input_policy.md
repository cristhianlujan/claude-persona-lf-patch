# Missing Input Policy

## Purpose
Prevent the worker from inventing simulator, tracking, consent or release assumptions.

## Allowed pipeline actions
- `CONTINUE_WITH_LOW_RISK_ASSUMPTIONS`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

## Never assume
- legal approval
- privacy consent
- tracking payload for sensitive data
- simulator eligibility logic
- conversion promise
- lead field requirement
- production readiness

## Required missing-input output
Use `schemas/simulator_missing_input.schema.json` and state missing fields, why needed, safe assumptions, blocked assumptions, recommended next gate and self-verdict.

## Research basis
- Internal LF: ACT-0015 and ACT-0045.
- Own repo: missing-input policies in existing profile packs.
- Critical/risk: privacy, QA, analytics and release controls.
- Adapted into: `contracts/missing_input_policy.md`.
- Reason for location: missing-input behavior is a reusable operational contract.
