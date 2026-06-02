# Activation Example — Governance Security Profile

## Input
User requests repair of governed profile/card assets after an assistant incident.

## Expected Classification
ROUTE_TO_ACT0045 / VERIFY_READBACK_ONLY.

## Expected Behavior
- Use Router-first.
- Read Supabase current source.
- Read GitHub current files.
- Compare against expected modular pack.
- Correct only missing candidate/read-only artifacts if allowed.
- Do not promote state.

## Expected Output
Final report with finding, correction, artifact matrix, readback, final state, and pending items.
