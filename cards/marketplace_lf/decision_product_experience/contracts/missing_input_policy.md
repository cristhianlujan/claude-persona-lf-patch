# Missing Input Policy — MarketPlace LF Decision Product Experience

Status: CANDIDATE_READ_ONLY

## Return `MARKETPLACE_DECISION_NEEDS_SOURCE` when

- Supabase active asset check is missing and the decision depends on official state.
- MarketPlace LF context source is missing.
- Candidate options are unclear and the user did not ask for a single direct decision.
- The affected surface is not declared.
- Legal/compliance dependency is present but not identified.
- The request depends on research not yet discovered.

## Return `RETURN_TO_ORCHESTRATOR` when

- The request belongs to a different LF project.
- The request is implementation-only and should go to Frontend Prototype Architect.
- The request is pure gamification architecture and should go to the Gamification System Architect.
- The request needs a new profile/skill rather than this card.

## Allowed assumptions

Only low-risk assumptions are allowed:

- Candidate naming format.
- Draft decision ID.
- Sandbox-only state.
- Minor formatting of output tables.

## Forbidden assumptions

- Do not assume legal validation.
- Do not assume production readiness.
- Do not assume Home official can be touched.
- Do not assume logos, partner names or claims are authorized.
- Do not assume GitHub pack is runtime-enabled.
- Do not assume Supabase writes are allowed.
