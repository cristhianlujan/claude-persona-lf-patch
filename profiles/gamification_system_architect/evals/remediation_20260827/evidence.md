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
`run_cases.py` exercises 17 cases:
- 2 positive structural candidates;
- 1 missing-input state;
- 12 negative/adversarial controls, including invented authority, unsafe activation/deactivation, vanity metric, guardrail loss, mechanic loss and counterfactual pressure trajectory;
- 1 fresh holdout;
- 1 malformed-input totality case.

The suite emits `evidence_class=STRUCTURAL_VALIDATOR_ONLY_NOT_PROFILE_EXECUTION` by design.

## Runtime-context hardening V2 — current main comparison
Comparison baseline for this pass: `main@b2fe89d63cbc041536a2634ee3bdbbcddc14a39b`.

Current UI Architect has a runtime-first authority/context resolution and self-repair invariant. The V2 Gamification patch adds the domain-equivalent safety behavior:
- consume supplied/resolved objective, guardrails and claim authority before missing-input classification;
- forbid re-asking resolved guardrail/authority;
- distinguish low-risk non-material proposals from material financial/safety truth;
- discard mechanics that improve engagement by pressure, punitive loss, harmful incentive or hidden persistence;
- self-repair once before output on pressure, unsupported strengthening, missing exit/off-condition or guardrail loss;
- require ethical judge to compare raw/resolved context, not only the mechanic in isolation;
- require Router/direct normalized mechanic consistency.

`runtime_context_cases.json` adds 7 fresh semantic cases: resolved-guardrail short-circuit, material financial truth unresolved, noncanonical proposal boundary, pressure counterfactual, unsafe reward, Router/direct divergence and a fresh clarity-progress holdout.

The semantic case catalog is explicitly `SEMANTIC_CASE_CATALOG_NOT_RAW_PROFILE_EXECUTION`.

## Immutable structural evidence reuse
The V2 patch does not modify the deterministic validator, schema or `run_cases.py`. Their exact blobs remain:
- validator: `5f56b9023b4c58ad510435a05832d8065407e8b4`;
- schema: `628c38df451b500f2d3ae3017524af557fe362b6`;
- runner: `cff4722b478c22104a293215f23cc4cd0d328940`.

Those immutable blobs are the same artifacts previously executed 17/17. The current pass still requires exact-head CI/readback and the new semantic/ethical layer before merge; prior execution is not treated as RAW runtime behavior.

## Evidence ceiling
These fixtures prove contract/validator and semantic-case coverage of the candidate package only. They do not prove an external runtime profile execution. A real behavioral claim still requires literal input + RAW output + canonical execution receipt + semantic judge + ethical judge + fresh holdout/adversarial evidence under `EJECUCION_PERFIL_LF`.
