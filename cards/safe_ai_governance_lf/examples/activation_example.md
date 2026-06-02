# Activation Example — Safe AI Governance Card

## Input
User asks to continue a governed correction without microapprovals.

## Expected Classification
ROUTE_TO_SKILL or VERIFY_ONLY inside confirmed scope.

## Expected Behavior
- Classify the request before action.
- Use Supabase/GitHub readback for current state.
- Preserve official protocol ownership.
- Continue only within authorized correction scope.
- Do not promote state or enable runtime.

## Expected Output
Closed mode with evidence and no unauthorized write/state change.
