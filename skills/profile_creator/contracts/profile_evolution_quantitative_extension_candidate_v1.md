# Profile Evolution — quantitative methods extension (candidate v1)

**Scope:** Add five optional mathematical/statistical method packs to the five already identified corrections. No autonomous engine, no separate selector, no model adapter, no model invocation, no new policy authority, no Profile Updater admission, no cutover.

## Existing five corrective fronts (not yet implemented by this extension)

1. `CAPABILITY_SELECTOR`: require evidence-driven choice with an explicit, inspectable reason if no extra capabilities are necessary.
2. `SPECIALIZE` contract: distinguish truly empty composition from missing data, with a typed `NO_ADDITIONAL_CAPABILITY_NEEDED` decision and preserved constraints.
3. `MODE_CONTRACT_COMPLETE` validator: check consistency between frozen selection, applicable methods and execution; never invent capabilities to fill a list or alter archived benchmark scores.
4. Behavior evaluator: compare original and evolved RAW answers on matched domain tasks with blind evaluation, preservation and critical regressions.
5. GPT Native independence: distinguish second-chat separation from authentic provider/orchestrator attestation and `dependency/data/author` assurance. The current independent FAIL must be preserved, not promoted.

## Additional optional quantitative methods

| # | Method | Apply only when | Mathematical core | Evidence / failure condition |
|---|---|---|---|---|
| 6 | `EVIDENCE_VALUE_OF_INFORMATION` | A new probe competes with other probes and calibrated outcome likelihoods exist | `IG(q)=H(H)-E_y[H(H|y,q)]`; choose by positive expected information gain subject to trusted measurement cost | Without priors/likelihood provenance: `UNPROVEN`; do not invent distributions. For duplicate reads, compare exact bound evidence refs (cheap preliminary check, not a sufficiency oracle). |
| 7 | `CALIBRATED_HYPOTHESIS_UPDATE` | Competing hypotheses have independently calibrated priors and likelihoods | `P(H|E)=P(E|H)P(H)/P(E)` | Missing calibration, impossible evidence or reused observation masquerading as independent: block probabilistic conclusion. Not a causal proof. |
| 8 | `CAUSAL_ALTERNATIVE_CHALLENGE` | Multiple candidate causes/repairs need differentiation | Explicit causal DAG, first-bad-boundary and intervention/counterfactual checks; do not infer `do(X)` from mere correlation | Root/effect/provenance and assumptions required; if no intervention or identification, report hypothesis, not causal certainty. Reuse `CAUSAL_EFFECT_LINEAGE` if applicable. |
| 9 | `PAIRED_BEHAVIOR_STATISTICS` | There are real matched GPT Native RAW outputs, a frozen rubric, independent judges and holdout | `delta_i=Q_evolved_i-Q_original_i`; fixed-seed paired bootstrap 95% CI and critical-regression count | Reuse existing paired-bootstrap scorer/benchmarks; do not create a new statistics engine, tune after RAW, or score document presence as expertise. Small single-case pilot remains qualitative. |
| 10 | `PARETO_METHOD_BUDGET` | Two or more methods have genuinely observed quality, latency, cost, regression-risk vectors | Keep nondominated alternatives; A dominates B iff at least as good on every objective and strictly better on >=1 | Missing observed metrics: `UNPROVEN`; does not auto-select or authorize admission. |

## Reuse boundary

- `PROFILE_ASSESSMENT` and existing `CAPABILITY_SELECTOR` decide **which optional method to run**, using typed signals and existing governed catalog. None of the candidate checks makes its own global selection.
- `METHOD_PACK_REGISTRY` is the governed catalog authority; register only after positive and negative empirical tests.
- `INDEPENDENT_ASSURANCE` remains the only admissible independent-review boundary.
- `public.lf_capability_current` currently includes `CAPABILITY_SELECTOR` and `CAUSAL_EFFECT_LINEAGE`; do not introduce equivalent parallel providers.
- All durable policies, capability registrations, execution evidence and EKB belong in Supabase; source implementation and tests live in GitHub. No Excel persistence.
- GPT Native only; no Llama and no surrogate API run.
- Candidate helper `quantitative_method_checks_candidate_v1.py` is side-effect-free and is **not** attached to profile runtime, admission or selector until separately proven.

## R3 Reparador provenance / limitation

Recent Reparador V7/R3 experiment was reported to have 29/29 internal checks, RC-079 changed one decision and avoided one repeated read; RC-080 had no decision change. It was an auxiliary probe/progress optimizer, not a replacement of the V7 dynamic selector or a completed blinded judge comparison. Do **not** infer statistical or domain-task uplift from those counts.

## Admission experiment — real behavior, not synthetic math tests

1. Freeze original/evolved GPT Native profile snapshots, independent judge rubric and domain-task cases before RAW collection.
2. Produce matched blind RAW on real `quality_pack`, `ui_architect`, `product_director_lf` and Reparador tasks, including repeats, contradictory evidence and important negative controls.
3. For each method compare **same case with/without method**: answer quality, required evidence acquired, repeated reads, diagnosis/decision changes, first-bad-boundary correctness, critical regressions, time/cost observed and human intervention.
4. Predefine hypothesis, minimal material effect, holdout, sample-size/power and statistical rule; compute paired bootstrap using existing scorer. Do not invent an uplift threshold or declare expertise from protocol tests.
5. Admit only method-specific gains with true independent provenance and zero critical regressions; otherwise retain as candidate or retire. No PE10_C3 PASS or v0.2 activation implied.

## Candidate utility tests

Run `python skills/profile_creator/evals/test_quantitative_method_checks_candidate_v1.py`.
They test math invariants and fail-closed behavior only. They do not execute GPT Native or prove independent expertise.
