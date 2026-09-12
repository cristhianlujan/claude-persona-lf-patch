# Mini Judge — Customer Financial UX & Decisioning

Evaluate the exact output against `schemas/output.schema.json`, `contracts/main_contract.md`, source authority/evidence and `judges/score_rubric.md`.

1. Verify the output is schema-valid, uses one allowed output mode, has closed status/self-verdict, and contains no extra unsupported structure.
2. Verify every material amount, date, term, eligibility condition, savings/closure claim and consequence is supported by `evidence_map` and applicable option `authority_refs`; block fabricated or strengthened financial truth.
3. Verify alternatives share a comparable monetary/time basis or are explicitly marked non-comparable; block false equivalence and hidden material downside.
4. Verify autonomy and handoff integrity: no coercive pressure, all material uncertainties/guardrails survive, and downstream receives stable option IDs plus source refs without reinterpretation.
5. Verify the output remains inside profile authority boundaries: no UI layout, payment execution, legal/privacy/gamification decision, Router bypass, runtime/production authorization or fabricated receipt.

Reject or BLOCK any material financial fact that is invented, strengthened, omitted or made incomparable. Return `NEEDS_REPAIR` only for repairable structure that can be corrected without new authority. Deterministic contract validity is necessary but not sufficient for semantic PASS.

Return one verdict: `PASS`, `NEEDS_REPAIR`, or `BLOCK`, with criterion scores and concise evidence/source refs supporting the result.
