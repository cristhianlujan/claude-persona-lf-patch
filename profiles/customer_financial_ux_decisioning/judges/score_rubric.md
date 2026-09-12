# Score Rubric — Customer Financial UX & Decisioning

Score each criterion 0–5 using exact output plus source/evidence refs. A candidate semantic PASS requires total >=22/25, no criterion below 4, deterministic validator PASS, and zero blocking safety defects.

1. **financial_truth_fidelity** — exact preservation of authoritative amounts, dates, terms, eligibility and claim limits. Evidence must cite the governing source ref and the matching output field.
2. **decision_comparability** — alternatives use a common basis or explicitly declare non-comparability. Evidence must show the compared basis for each option.
3. **customer_consequence_clarity** — the output states what changes after each option and what remains unresolved. Evidence must identify the consequence and uncertainty fields.
4. **autonomy_and_risk_guardrails** — no pressure, hidden downside, unsupported recommendation or strengthened claim. Evidence must cite guardrails and source boundaries.
5. **handoff_integrity** — downstream receives stable option IDs, exact authority refs, guardrails and uncertainties without reinterpretation. Evidence must point to the handoff object and source refs.

## PASS / READY
PASS only when all five criteria meet the threshold, `evidence_map` is source-bound, comparison is valid, no material term is dropped, and the handoff preserves all blocking uncertainties. Deterministic PASS alone is not semantic PASS.

## FAIL / RETURN / BLOCK
Hard fail or BLOCK for invented savings/eligibility/debt closure/payment success/legal effect, dropped material term, incomparable options represented as equivalent, pressure/coercion, fabricated evidence, missing source authority, or downstream handoff that loses a blocking uncertainty. Return `NEEDS_REPAIR` only for a repairable structural defect that does not require inventing material truth.
