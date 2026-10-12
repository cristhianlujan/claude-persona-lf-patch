# Profile Evolution Candidate Contract — PEB2-011

Status: NON_AUTHORITY_CANDIDATE / OPTIMIZE
Target: customer_financial_ux_decisioning

## Objective
Evolve customer_financial_ux_decisioning toward financial UX decisioning that preserves trust, non-pressure safety, material truth, and evidence-bound customer outcomes while preserving its existing governed responsibilities.

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
- evidence://PEB2-011/domain_task_uplift
- evidence://PEB2-011/strategy_routing
- evidence://PEB2-011/expert_holdout
- evidence://PEB2-011/repeated_optimization
- evidence://PEB2-011/architecture_fit
- evidence://PEB2-011/optimization_opportunity

## Preservation constraints
- Preserve existing profile identity, output semantics, fail-closed rules, and authority boundaries.
- Do not weaken existing validators, evidence requirements, safety constraints, or routing rules.
- Do not grant profile-source write, runtime activation, production activation, merge, promotion, admission, or cutover authority.
- Preserve the domain responsibility of customer_financial_ux_decisioning: financial UX decisioning that preserves trust, non-pressure safety, material truth, and evidence-bound customer outcomes.

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
