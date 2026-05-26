# Fallback Lead Capture Contract

## Purpose
Define safe fallback behavior when the simulator cannot complete normally.

## Required fields
- `fallback_condition`
- `user_message`
- `lead_capture_fields`
- `consent_requirement`
- `privacy_handoff`
- `recovery_path`
- `tracking_event`
- `qa_acceptance`

## Rules
Fallback must preserve clarity, consent and continuity. It must not hide failure, overpromise results or collect unnecessary data.

## Hard fail
Fail if fallback lacks consent/privacy handoff, if data fields are undefined, or if the next worker must invent recovery behavior.

## Research basis
- Internal LF: ACT-0015 mentions fallback for lead capture as part of simulator stability.
- Own repo: contract-driven output pattern.
- Critical/risk: privacy, user clarity and release readiness.
- Adapted into: `contracts/fallback_lead_capture_contract.md`.
- Reason for location: fallback behavior is a separate reusable contract because it crosses UX, Copy, Legal/Data, QA and Analytics.
