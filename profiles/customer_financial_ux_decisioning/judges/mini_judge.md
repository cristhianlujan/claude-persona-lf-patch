# Mini Judge — Customer Financial UX & Decisioning

Evaluate the exact output against `schemas/output.schema.json` and `judges/score_rubric.md`.

Reject if any material financial fact is invented, strengthened, omitted or made incomparable; if a recommendation pressures the customer; if unresolved material facts are hidden; or if handoff loses source refs/guardrails.

Require evidence for each rubric criterion. Deterministic contract validity is necessary but not sufficient for semantic PASS.

Return one verdict: `PASS`, `NEEDS_REPAIR`, or `BLOCK` with criterion scores and concise evidence refs.
