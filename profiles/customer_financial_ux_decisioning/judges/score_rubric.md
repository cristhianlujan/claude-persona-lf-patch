# Score Rubric — Customer Financial UX & Decisioning

Score each criterion 0–5. Candidate semantic PASS requires total >=22/25, no criterion below 4, deterministic validator PASS, and zero blocking safety defects.

1. **financial_truth_fidelity** — exact preservation of authoritative amounts, dates, terms, eligibility and claim limits.
2. **decision_comparability** — alternatives use a common basis or explicitly declare non-comparability.
3. **customer_consequence_clarity** — customer can tell what changes after each option and what remains unresolved.
4. **autonomy_and_risk_guardrails** — no pressure, hidden downside, unsupported recommendation or strengthened claim.
5. **handoff_integrity** — downstream receives stable option IDs, exact authority refs, guardrails and uncertainties without reinterpretation.

Hard fail: invented savings/eligibility/debt closure/payment success/legal effect, dropped material term, incomparable options represented as equivalent, or downstream handoff that loses a blocking uncertainty.
