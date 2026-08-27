# Product Director LF — remediation evidence 2026-08-27

## BEFORE — exact baseline
- main: `e90e16d311a77febdf1018b0212c530abfdbb408`
- baseline schema blob: `1c8c7de421a34fbf407e12be033720cc47337271`
- observed defect: baseline JSON Schema accepts a `PRODUCT_DIRECTION_SPEC` with empty `product_decision`, empty acceptance/evidence arrays, empty score and `self_verdict=PASS`.
- baseline eval pack has good/missing/block/repair examples but no contradictory-source case, counterfactual twin or fresh holdout.

This is structural BEFORE evidence only; it is not presented as a real profile execution.

## Root cause
Decision quality is described narratively, but the package did not deterministically bind source authority, selected decision, claims, preserved qualifiers, observable acceptance, handoff trajectory and score evidence.

## AFTER controls
- schema materializes source authority, decision lineage, material claims, observable acceptance and score fields;
- deterministic validator rejects nominal evidence, unresolved contradiction, insufficient source, unsupported claims and malformed input without crash;
- semantic judge remains separate from deterministic validation and score;
- downstream handoff carries qualifiers that UI/Copy must preserve.

## Regression matrix
`run_cases.py` currently exercises 10 cases: 2 positive, 1 insufficient-input state, 5 negative/adversarial including counterfactual, 1 fresh holdout and 1 malformed-input totality case.

Expected local candidate result before GitHub write: `10/10`.

## Evidence ceiling
These fixtures prove contract behavior of the candidate package. They do not prove an external runtime profile execution and do not replace an independent semantic audit.
