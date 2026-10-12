# Profile Evolution Candidate Contract — PEB2-010

Status: NON_AUTHORITY_CANDIDATE / OPTIMIZE
Target: product_director_lf

## Objective
Evolve product_director_lf toward evidence-bound product decisions with causal hypotheses, explicit alternatives, measurable outcomes, and preserved business constraints while preserving its existing governed responsibilities.

## Optimization loop
- Baseline: exact-source current profile behavior on frozen cases
- Signal: paired capability score, false-pass rate, preservation and holdout delta
- Compare: same GPT_NATIVE route for baseline and candidate with fixed paired scorer
- Stop: no positive holdout delta, any critical regression, insufficient evidence, or method budget breach

## Capability composition
- CAUSAL_EFFECT_LINEAGE
- INDEPENDENT_ASSURANCE
- PERFORMANCE_EXACT_SOURCE_BENCHMARK

## Evidence refs
- evidence://PEB2-010/domain_task_uplift
- evidence://PEB2-010/strategy_routing
- evidence://PEB2-010/expert_holdout
- evidence://PEB2-010/repeated_optimization
- evidence://PEB2-010/architecture_fit
- evidence://PEB2-010/optimization_opportunity

## Preservation constraints
- Preserve existing profile identity, output semantics, fail-closed rules, and authority boundaries.
- Do not weaken existing validators, evidence requirements, safety constraints, or routing rules.
- Do not grant profile-source write, runtime activation, production activation, merge, promotion, admission, or cutover authority.
- Preserve the domain responsibility of product_director_lf: evidence-bound product decisions with causal hypotheses, explicit alternatives, measurable outcomes, and preserved business constraints.

## Validation plan
- Materialize outside the authority repository and prove source_unchanged=true.
- Run existing deterministic/profile-local validation on the candidate overlay where applicable.
- Compare baseline and candidate behavior on frozen profile-domain cases.
- Require holdout improvement with zero critical regressions before admission.

## Stop conditions
- Stop and request evidence when a material capability claim is unsupported.
- Stop on any authority, provenance, safety, or preservation regression.
- Stop optimization when holdout fails to improve or cost exceeds the frozen method budget.

## Rollback
Discard the reversible overlay; canonical profile source remains byte-identical.

## Authority boundary
This candidate does not write profile authority, activate runtime, activate production, admit itself, merge itself, or replace independent assurance.
