# Product Director LF — remediation evidence 2026-08-27

## BEFORE — exact baseline
- main: `e90e16d311a77febdf1018b0212c530abfdbb408`
- baseline schema blob: `1c8c7de421a34fbf407e12be033720cc47337271`
- observed defect: baseline JSON Schema accepts a `PRODUCT_DIRECTION_SPEC` with empty `product_decision`, empty acceptance/evidence arrays, empty score and `self_verdict=PASS`.
- baseline eval pack has good/missing/block/repair examples but no contradictory-source case, counterfactual twin or fresh holdout.

This is structural BEFORE evidence only; it is not presented as a real profile execution.

## Root cause
Decision quality was described narratively, but the package did not deterministically bind source authority, selected decision, claims, preserved qualifiers, observable acceptance, handoff trajectory, cross-artifact consistency and score evidence.

The UI remediation established two reusable lessons applied here:
- provenance/receipt proves execution, not semantic correctness;
- a fixture suite is not evidence that the profile actually produced the expected RAW decision.

## AFTER controls
- schema materializes source authority, decision lineage, material claims, observable acceptance, conflict resolution and exact score evidence fields;
- deterministic validator rejects nominal evidence, unresolved contradiction, insufficient/weak source authority, invented claim refs, cross-artifact decision mismatch, qualifier loss and malformed input without crash;
- material claims require an observed `AUTHORITATIVE` or `CONSTRAINT` source, not a merely non-empty URI or contextual note;
- semantic judge separately checks whether the selected decision actually resolves the product objective and preserves authority/constraints;
- downstream handoff carries qualifiers that UI/Copy must preserve;
- `behavioral_eval_protocol.md` requires RAW output + canonical execution receipt + semantic judge + fresh holdout/adversarials before any behavioral remediation claim.

## Structural regression matrix
`run_cases.py` now exercises 14 cases:
- 3 positive structural candidates, including a properly resolved source conflict;
- 1 insufficient-input state;
- 8 negative/adversarial controls, including weak authority, counterfactual trajectory, cross-artifact mismatch and qualifier loss;
- 1 fresh holdout;
- 1 malformed-input totality case.

The suite emits `evidence_class=STRUCTURAL_VALIDATOR_ONLY_NOT_PROFILE_EXECUTION` by design.

## Evidence ceiling
These fixtures prove contract/validator behavior of the candidate package only. They do not prove an external runtime profile execution, a semantic judge PASS, Router/direct consistency, or independent remediation verification.

Behavioral closure must follow `behavioral_eval_protocol.md`.
