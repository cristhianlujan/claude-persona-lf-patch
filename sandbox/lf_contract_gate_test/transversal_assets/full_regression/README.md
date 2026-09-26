# FULL_REGRESSION

Canonical identity: `FULL_REGRESSION` / `TRANSVERSAL_FULL_REGRESSION`.

## Estado y Owner

- Owner: `LF_GOVERNANCE`
- Tipo: transversal CI plan consumer/verifier.
- Estado documental: `VIGENTE`.
- Estado operativo candidato: `READ_ONLY`.
- Runtime: `NO_HABILITADO`.
- Inventory status: `FORMAL_TRANSVERSAL_REGISTERED_NOT_CUTOVER`.
- Promotion status: `READY_FOR_PROMOTION` only after deterministic + semantic + exact-head CI proof for the current candidate head.
- `FULL_REGRESSION` is **not** a Router, applicability engine, registry, validator bundle, or carrier.

## Propósito

Verify that a governed CI applicability plan was executed exactly once by its canonical carriers, with compatible receipts and no extra controls.

It protects these invariants:

- `LOCAL_APPLICABILITY_DECISIONS = 0`
- `PLANNED_CONTROLS = EXECUTED_CONTROLS`
- `UNPLANNED_EXECUTIONS = 0`
- `DUPLICATE_CONTROL_EXECUTIONS = 0`
- `RETIRED_CONTROL_EXECUTIONS = 0`
- `PARALLEL_APPLICABILITY_ENGINE = 0`
- `FAIL_OPEN_CASES = 0`
- `PARALLEL_ACTIVE_PATHS = 0`

## Cuándo consumirlo

Consume `FULL_REGRESSION` only after Changeset Governance and the canonical execution plan have already resolved applicability for the exact candidate revision. It is appropriate for manual/main verification, authority-change verification, promotion proof and post-merge verification; it is never an applicability fallback.

## Cómo consumirlo

1. obtain the governed `lf-ci-execution-plan/v2`;
2. verify its currentness/source authority and deterministic `plan_sha256`;
3. let only the canonical carriers execute their own `carrier_controls`;
4. collect exactly one compatible `lf-ci-carrier-receipt/v1` per planned carrier;
5. pass plan + receipts to `full_regression_v1.py`;
6. require exact `planned == executed`, zero extras, zero duplicates and zero retired controls;
7. accept `NOT_APPLICABLE` only when `required_controls=[]`, with zero execution.

## Qué hace

1. consumes the already-resolved `lf-ci-execution-plan/v2`;
2. validates plan integrity/SHA/currentness contract;
3. resolves the carrier partition already present in the plan;
4. consumes one compatible receipt per required canonical carrier;
5. verifies exact planned/executed equality;
6. blocks duplicates, retired controls, stale or incompatible receipts;
7. emits `lf-full-regression-receipt/v1`;
8. returns `NOT_APPLICABLE` with zero executions when the governed plan contains no controls.

## Qué NO hace

- does not determine Applicability;
- does not classify paths;
- does not add controls because the run is “full”;
- does not execute controls owned by another carrier;
- does not create another Router;
- does not create another registry;
- does not replace Changeset Governance;
- does not turn an invalid plan into “run everything”;
- does not manufacture PASS by executing non-applicable controls.

## Authority

Authority is intentionally split by concern; no support surface may replace it:

- GitHub: canonical source, wiring, tests, workflows and README contract.
- Supabase sandbox: canonical operational identity, metadata, materialized asset relationships, lifecycle state and EKB.
- Drive: supporting inventory/readback only; it is **not** an authority source for code, lifecycle or relationships.

Applicability authority:

`CHANGESET_GOVERNANCE_LF_V1 → LF_CI_EXECUTION_PLAN_V2`

Currentness authority:

`CURRENTNESS_AUTHORITY` through `lf_ci_currentness_bridge_v1.py`.

`FULL_REGRESSION` consumes those decisions. It cannot override them.

## Descubrimiento y ubicación

Lookup order for agents/auditors:

1. `public.lf_activos` with `codigo_activo=FULL_REGRESSION` for identity, state, owner, paths and metadata;
2. `public.lf_activo_relaciones` for materialized structural dependencies/consumers;
3. this README for the consumption contract and physical surfaces;
4. the existing source files and registries listed below for exact wiring;
5. Drive inventories only as supporting snapshots/readback.

While candidate/not-cutover, the active transversal index must not falsely present this asset as operationally active. The repository transversal index contains a non-active candidate locator instead.

## Inputs

Required:

- governed `lf-ci-execution-plan/v2`;
- canonical carrier receipts `lf-ci-carrier-receipt/v1` for every carrier present in `carrier_controls`.

Optional hard guards:

- expected exact source revision;
- explicit retired-control set.

Input contract is validated before any PASS or `NOT_APPLICABLE` receipt is emitted.

## Outputs

`lf-full-regression-receipt/v1` containing:

- asset/canonical identity;
- source `plan_sha256`;
- applicability decision;
- planned and executed controls;
- consumed carrier receipt digests;
- zero-count invariants for unplanned, duplicate, retired, parallel and fail-open execution;
- deterministic `receipt_sha256`.

## Consumers

Direct verification contexts in this candidate are CI self-tests/readback, PR promotion proof and post-main verification after an authorized merge.

`GITHUB_CONTRACT_GATE_LF` is an `UPSTREAM_TRANSITIVE_CONSUMER`: its governed CI path depends transitively on the `FULL_REGRESSION` plan/verification contract, but it is **not** a direct caller that delegates its owned controls to `full_regression_v1.py`.

The existing workflows remain carriers of their own controls; they are not consumers that delegate execution to `FULL_REGRESSION`.

## Dependencies

Canonical logical dependencies:

- `CHANGESET_GOVERNANCE_LF_V1` — applicability authority;
- `LF_CI_EXECUTION_PLAN_V2` — governed execution plan contract;
- `CI_FAST_DEEP_LANE_ROUTER` — materialized structural dependency;
- `CURRENTNESS_AUTHORITY` — materialized structural dependency/currentness participant;
- `lf_ci_control_impact_registry_v2.json`;
- `lf_shared_ci_control_ownership_registry_v1.json`;
- the three existing canonical workflow carriers.

No dependency grants local applicability authority to this asset.

## Relaciones materializadas

The durable graph in `public.lf_activo_relaciones` is required for asset-to-asset relationships that have canonical `lf_activos` identities:

- `FULL_REGRESSION --DEPENDE_DE--> CI_FAST_DEEP_LANE_ROUTER`;
- `FULL_REGRESSION --DEPENDE_DE--> CURRENTNESS_AUTHORITY`;
- `GITHUB_CONTRACT_GATE_LF --CONSUME_TRANSITIVAMENTE--> FULL_REGRESSION`.

Logical authorities without their own `lf_activos` identity remain contractual dependencies in metadata/README and must not be fabricated as asset rows solely to complete a graph.

For retirement and health audits, incoming consumer checks must see the `GITHUB_CONTRACT_GATE_LF` relation so `FULL_REGRESSION` cannot be treated as orphaned.

## Applicability

`FULL_REGRESSION` may be requested for manual/main/authority-change verification, but the request **never changes the set of controls**.

The governed plan remains the only source of:

- `required_controls`;
- `not_applicable_controls`;
- `carrier_controls`;
- dependency closure.

A legacy `full_regression_controls` field may still exist in the impact registry for compatibility/readback, but its semantics are `HISTORICAL_COMPATIBILITY_IGNORED_FOR_APPLICABILITY`.

## Canonical carriers

Exactly the existing carriers:

- `LF_CONTRACT_CHECK` → `.github/workflows/lf-contract-check.yml`
- `VALIDATE_LF_PACKS` → `.github/workflows/validate-lf-packs.yml`
- `LF_DB_REGRESSION` → `.github/workflows/lf-db-regression.yml`

`FULL_REGRESSION` is not a fourth carrier.

## Receipts

Each required carrier supplies one `lf-ci-carrier-receipt/v1` bound to:

- the same `plan_sha256`;
- the expected exact source revision when present;
- exactly its planned control subset;
- PASS results for those controls.

Missing, duplicate, extra, wrong-SHA or wrong-revision receipts block.

## Fail-closed / límites

Blocking conditions include:

- plan missing/corrupt/incomplete;
- unresolved applicability;
- stale/unready source authority;
- carrier unknown or missing;
- receipt missing/incompatible/corrupt;
- planned/executed mismatch;
- duplicate control execution;
- retired control planned/executed.

`NOT_APPLICABLE` is valid only when `required_controls=[]`; it emits zero execution and accepts zero carrier receipts.

There is no fallback from invalid evidence to “run everything”:

`invalid/unresolved input → BLOCK`

not:

`invalid/unresolved input → expand controls`.

## Lifecycle

`CREATE → REGISTER_CANDIDATE → REVIEW → SANDBOX_TEST → READY_FOR_PROMOTION → MERGE_AUTHORIZED → MAIN_READBACK → ACTIVATE_AUTHORIZED → VERIFY → DEPRECATE/ROLLBACK`

This PR may reach `READY_FOR_PROMOTION`. Merge, runtime activation or productive mutation require separate authorization.

## Observability

The receipt exposes deterministic counters:

- local applicability decisions;
- unplanned executions;
- duplicate control executions;
- retired control executions;
- parallel active paths;
- fail-open cases.

All must be zero for PASS.

Data-health readback additionally verifies:

- one non-archived `public.lf_activos` row for `FULL_REGRESSION`;
- expected materialized relationship set with no duplicate relation tuple;
- metadata consumer/dependency declarations consistent with the materialized graph;
- documented test paths correspond to tests actually executed in exact-head CI;
- candidate source revision equals the PR exact head used for evidence.

## Registries

Reused canonical registries only:

- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_shared_ci_control_ownership_registry_v1.json`

Supabase identity and relationship registries:

- `public.lf_activos` with `codigo_activo=FULL_REGRESSION`;
- `public.lf_activo_relaciones` for canonical asset-to-asset edges.

No row is required in `public.lf_capability_registry` or `public.lf_operation_registry` solely to create identity.

## Código físico

Implementation:

- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py`

Applicability/plan authority consumed:

- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_currentness_bridge_v1.py`

Semantic judge:

- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py`

## Superficies canónicas

- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/README.md`
- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py`
- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_currentness_bridge_v1.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_shared_ci_control_ownership_registry_v1.json`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json`
- `sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md`
- `.github/workflows/lf-contract-check.yml`
- `.github/workflows/validate-lf-packs.yml`
- `.github/workflows/lf-db-regression.yml`

## Tests

Material deterministic/integration coverage:

- `sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/test_ci_control_carrier_wiring_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_currentness_bridge_v1.py`

The CI router self-test currently executes seven checks; only the four above are declared as material `FULL_REGRESSION` test paths because they directly cover this asset's plan/wiring/currentness surfaces.

E2E cases covered:

- A: real `NOT_APPLICABLE`, zero execution;
- B: partial applicability, `planned == executed`;
- C: external canonical carriers produce receipts, `FULL_REGRESSION` consumes them, zero duplication;
- D: invalid plan blocks;
- E: former run-everything behavior does not return.

## Deterministic criteria

PASS requires P1–P8 deterministic evidence, exact plan/receipt hashes, exact carrier partition, and all zero invariants.

A related test passing is not evidence for another point.

## Semantic criteria

Independent judge:

`sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py`

It evaluates P1–P8 plus identity, owner, duplicate/orphan responsibility, parallel paths, README, registry, implementation, execution fidelity, discoverability and relationship documentation.

## Validación y readback

Before promotion require:

- deterministic P1–P8 PASS;
- semantic P1–P8 PASS;
- E2E A–E PASS;
- exact-head CI green for the three canonical carriers;
- README/implementation/registry exact-head readback;
- Supabase identity + relation + metadata readback;
- supporting Drive inventory updated with the same candidate identity/head without promoting Drive to authority;
- `INVALID_RESIDUAL=0`;
- `UNPLANNED_EXECUTIONS=0`;
- `DUPLICATE_CONTROL_EXECUTIONS=0`.

After an authorized merge, repeat main readback, Supabase readback, E2E execution and real consumer/receipt verification before `COMPROBADO=YES` is possible.

## No duplicación

Do not create:

- another FULL_REGRESSION;
- another Router;
- another applicability engine;
- another registry;
- another carrier path;
- another currentness engine.

Extend the existing authorities and consume their receipts.

## Currentness

`refs/heads/main` remains the moving authority. The source revision recorded for a candidate is historical evidence, not a replacement authority.

`lf_ci_currentness_bridge_v1.py` includes `transversal_assets/full_regression/**` in the CI authority material selectors so a future material change cannot silently bypass currentness evaluation.

## Relation with CHANGESET_GOVERNANCE_LF_V1

Changeset Governance owns classification/applicability input. `FULL_REGRESSION` is downstream and cannot decide locally that a control applies.

Changing the declarative legacy full-regression list alone must not change planned controls.

## COMPROBADO

`PASS` is not `COMPROBADO`.

`COMPROBADO=YES` additionally requires merged `main`, post-main readback, real execution, real carrier receipts, a real consumer and post-main Supabase/readback evidence. Before authorized merge, the maximum valid state is `READY_FOR_PROMOTION` and `COMPROBADO=NO`.
