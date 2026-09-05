# Mini Judge — Customer Identity, Consent & Privacy

Evaluate exact output against `schemas/output.schema.json` and `judges/score_rubric.md`.

Reject inferred or bundled consent, over-collection, purpose drift, unnecessary raw sensitive-data exposure, invented retention/sharing/biometric/profiling authority, identity-verification claims without evidence, or a handoff that loses required/optional or purpose boundaries.

Return `PASS`, `NEEDS_REPAIR`, or `BLOCK` with criterion scores and concise evidence refs. Deterministic validity is necessary but not semantic/privacy approval.
