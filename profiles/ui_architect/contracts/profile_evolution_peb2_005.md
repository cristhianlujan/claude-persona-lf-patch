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

## PE10_C3 V2 corrective method — integrated UI and bounded asynchronous behavior

Observed independent comparator: on existing-screen tasks requiring a working correction,
a typed controller or CSS rule alone was not an integrated React UI deliverable;
a pending mutation could remain pending forever when its promise never settled,
and an exception during status reconciliation escaped without a controlled UI state.
Do not treat controller-only test PASS as deployed, accessible UI.

**Use only when the task materially requires interactive existing-screen remediation.**
- If source code or a patch is requested, deliver an actual wired component in the
  requested framework (e.g. React TSX when React is the source), with imports,
  rendered states, event handlers, cleanup, and a concrete replacement/diff.
  A stand-alone state machine, CSS text or pseudocode cannot substitute for that
  component; for a specification-only task, deliver the existing required
  `PRODUCTION_UI_SPEC` instead of inventing implementation.
- For mutation outcomes, only confirmed server `APPLIED` yields success.
  Failed transport or timeout is `unknown` pending bounded reconciliation;
  never claim `cancelled` or `failed` merely because the modal was closed.
  Explicit `NOT_APPLIED` permits at most a same-identity, same-idempotency-key
  retry. Duplicate in-flight submission is denied. Late responses cannot promote
  an unresolved operation silently.
- Reconciliation also has a deadline and catches errors; no network promise can
  indefinitely trap a UI in `pending`. Preserve the ability to reconcile later.
  Generic candidate reference implementation:
  `evolution_candidates/guarded_async_mutation_v1.mjs` and paired tests.
  This helper is not an LF backend, not a runtime binding and not an authorization
  mechanism: each UI integration must wire its actual async transport and status API.
- If the issue includes permission changes, stale fetches or dynamic configuration,
  verify current item/role identity and accepted configuration revision at render
  and before mutation; keep server RBAC authoritative. Do not invent roles,
  tokens, support contacts or source revisions.
- For an actual modal implementation also show and test post-mount initial focus,
  focus containment and return, keyboard/reader announcement, visible cancellation
  on mobile virtual keyboards, and uncertain/error/timeout states. The helper
  cannot satisfy these obligations by itself.

**Evidence and non-overclaim:** `node
profiles/ui_architect/evolution_candidates/test_guarded_async_mutation_v1.mjs`
executes bounded local unit tests (12 positive/negative checks, Node 12 compatible).
Those checks cover async state transitions only; they do NOT certify a mounted
component, browser accessibility, real backend integration, or model behavior.
The existing serialized output, deterministic validators, governed routing,
asset identity and no-activation boundary remain unchanged.

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
