# Score Rubric — Customer Financial UX & Decisioning

Score each criterion 0–5 using exact output plus current source/evidence refs. A candidate semantic PASS requires total >=22/25, no criterion below 4, deterministic validation PASS, dedicated semantic judge PASS and zero blocking safety defects.

A high score is invalid when the evidence is nominal, generic or self-referential. `PASS`, `clear`, `complete`, `customer friendly`, field presence or schema validity are not substantive evidence.

1. **financial_truth_fidelity** — exact preservation of authoritative amounts, dates, fees, terms, eligibility, debt/payment state and claim limits. Evidence must cite governing source refs and matching output fields. A 5 requires currentness/qualifier preservation and no unsupported strengthening.
2. **decision_comparability_and_causality** — alternatives use a common basis or explicitly declare non-comparability, and each option connects terms to observable immediate + downstream customer consequences. A 5 requires a real causal chain, not descriptive labels.
3. **tradeoff_and_counterfactual_depth** — the output explains why the decision changes between alternatives, ties any recommendation to an objective, identifies a plausible material change that would alter the decision boundary, and rejects at least one plausible alternative interpretation without inventing authority. Generic `key_tradeoff` text caps this criterion at 2.
4. **autonomy_uncertainty_and_risk_guardrails** — no pressure, hidden downside, unsupported recommendation or strengthened claim; unresolved material facts stay explicit; no business-conversion preference silently substitutes for customer decision logic. A 5 requires clear separation of known truth, uncertainty and proposal.
5. **handoff_integrity_and_postcondition** — downstream receives stable option IDs, exact authority refs, comparison basis, guardrails, material uncertainties and a postcondition that prevents UI/Copy/Tech from changing financial meaning. Generic handoff language caps this criterion at 2.

## PASS / READY
PASS only when all five criteria meet threshold and all of the following are true:
- `evidence_map` is source-bound;
- financial comparison is valid or explicitly non-comparable;
- no material term or qualifier is dropped;
- a decision-relevant causal consequence is observable for every material option;
- recommendation/ranking, if any, is justified by a governed objective;
- at least one counterfactual decision boundary is recoverable from the output + evidence;
- the handoff preserves all blocking uncertainties and the required downstream postcondition;
- semantic judge returns PASS.

Deterministic PASS alone is not semantic PASS.

## NEEDS_REPAIR
Use `NEEDS_REPAIR` when the answer is safe and structurally valid but materially shallow, including:
- consequences are generic labels rather than causal effects;
- trade-offs merely repeat amounts/dates;
- no decision boundary/counterfactual is recoverable;
- recommendation lacks a governed objective but can be removed/reframed safely;
- handoff is too generic to prevent downstream reinterpretation;
- evidence exists but does not substantively support the claimed reasoning.

## FAIL / BLOCK
Hard fail or BLOCK for invented savings/eligibility/debt closure/payment success/legal effect, dropped material term, incomparable options represented as equivalent, coercive pressure, fabricated evidence, unresolved material source conflict, unsupported strengthening, or downstream handoff that loses a blocking uncertainty.

A score cannot override a hard fail.
