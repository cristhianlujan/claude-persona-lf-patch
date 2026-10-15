# Profile Evolution Candidate Contract — PEB2-005

Status: NON_AUTHORITY_CANDIDATE / SPECIALIZE
Target: ui_architect

## Objective
Evolve ui_architect toward implementation-ready UI decisions that preserve semantic authority, resolve ambiguity safely, and make acceptance conditions observable while preserving its existing governed responsibilities.

## Specialization target
implementation-ready UI decisions that preserve semantic authority, resolve ambiguity safely, and make acceptance conditions observable

## Capability composition
- none beyond governed core

## Evidence refs
- evidence://PEB2-005/domain_task_uplift
- evidence://PEB2-005/strategy_routing
- evidence://PEB2-005/expert_holdout
- evidence://PEB2-005/repeated_optimization
- evidence://PEB2-005/architecture_fit
- evidence://PEB2-005/optimization_opportunity

## Preservation constraints
- Preserve existing profile identity, output semantics, fail-closed rules, and authority boundaries.
- Do not weaken existing validators, evidence requirements, safety constraints, or routing rules.
- Do not grant profile-source write, runtime activation, production activation, merge, promotion, admission, or cutover authority.
- Preserve the domain responsibility of ui_architect: implementation-ready UI decisions that preserve semantic authority, resolve ambiguity safely, and make acceptance conditions observable.

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
