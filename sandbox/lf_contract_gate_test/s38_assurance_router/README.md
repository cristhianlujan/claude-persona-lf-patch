# S38 → S36 assurance router v1

Purpose: automate the boundary between S38 governed-development evidence and S36 assurance without creating another transversal strategy or another test matrix.

The router is deliberately read-only. It never writes Supabase, never activates runtime/Golden/production, and never converts producer evidence into semantic proof. It accepts an exact frozen S38 review bundle, an out-of-band expected signer digest, and optionally an independent Quality Pack receipt.

Routing:

- no independent receipt → `WAIT_INDEPENDENT_REVIEW` in S38;
- independent `PASS_TO_COMPOSER` → export invariant candidates to S36;
- independent `PASS_WITH_RESTRICTIONS` → export to S36 with restrictions preserved;
- independent return/block verdict → route back to S38 repair;
- malformed identity, signer, authority, or independence → fail closed.

S36 remains owner of enrollment in the one canonical LF Test Matrix. This package only emits a normalized handoff candidate.

The accompanying transversal routing contract freezes the intended four-lane model: S30 hardens, S31 productizes reusable capabilities, S36 assures/regresses, and S38 governs identity/authority/evidence/trust. New findings route to a Work Package in those lanes by default; a new strategy is exceptional, not automatic.
