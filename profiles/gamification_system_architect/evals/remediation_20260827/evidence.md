# Gamification System Architect — remediation evidence 2026-08-27

## BEFORE — exact baseline
- main: `e90e16d311a77febdf1018b0212c530abfdbb408`
- baseline schema blob: `7060d06fdfb52ab7aff37c03be14906ac0103b53`
- observed defect: baseline JSON Schema accepts `GAMIFICATION_SYSTEM_SPEC` with empty target behavior, no metrics, no ethical/risk controls, empty score and `self_verdict=PASS`.
- baseline eval catalog is declarative and does not require reusable fixtures for activation/deactivation, vanity metrics, unsupported claims, counterfactual twins or holdout.

This is structural BEFORE evidence only; it is not presented as a real profile execution.

## Root cause
Safety was described narratively, but the package did not deterministically materialize and cross-bind `objective -> mechanic -> behavior -> risk -> metric -> guardrail`, activation/deactivation, claim authority, downstream preservation and evidence-bound scoring.

The UI remediation established two reusable lessons applied here:
- provenance/receipt proves execution, not semantic/ethical correctness;
- synthetic fixtures cannot substitute for RAW profile behavior.

## AFTER controls
- every material mechanic has activation, deactivation, acceptance, risk, metric, guardrails and authority refs;
- mechanic authority and financial claim authority must bind actual `system_lineage.source_refs`; a non-empty invented URI does not count;
- mechanic and metric IDs are unique and cross-referenced;
- handoff must preserve every material mechanic and its guardrails, plus risky-claim authority refs;
- vanity-only metrics cannot justify a mechanic;
- harmful financial incentives and pressure/clarity conflicts reject;
- semantic judge checks whether the mechanic actually resolves the objective and whether guardrails mitigate the stated risk;
- ethical judge remains a separate gate;
- `behavioral_eval_protocol.md` requires RAW output + canonical execution receipt + semantic/ethical judges + fresh holdout/adversarials before any behavioral remediation claim.

## Structural regression matrix
`run_cases.py` now exercises 17 cases:
- 2 positive structural candidates;
- 1 missing-input state;
- 12 negative/adversarial controls, including invented authority, unsafe activation/deactivation, vanity metric, guardrail loss, mechanic loss and counterfactual pressure trajectory;
- 1 fresh holdout;
- 1 malformed-input totality case.

The suite emits `evidence_class=STRUCTURAL_VALIDATOR_ONLY_NOT_PROFILE_EXECUTION` by design.

## Evidence ceiling
These fixtures prove contract/validator behavior of the candidate package only. They do not prove an external runtime profile execution, semantic/ethical judge PASS, Router/direct consistency, or independent remediation verification.

Behavioral closure must follow `behavioral_eval_protocol.md`.
