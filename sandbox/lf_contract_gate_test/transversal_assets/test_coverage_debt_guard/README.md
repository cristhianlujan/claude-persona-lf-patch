# TEST_COVERAGE_DEBT_GUARD

Capability candidate extracted from the historical `S36_ASSURANCE` umbrella.

## Purpose

Protect the accepted **global operation test-coverage debt** from growing during Full Regression / audit execution.

This capability is not an assurance-quality verdict and is not a normal changeset-scoped PASE control.

## Exact semantic contract

A PASS means only:

`ACCEPTED_TEST_COVERAGE_DEBT_NOT_GROWING`

It does **not** mean:

- all operational operations are covered;
- tests passed;
- semantic quality passed;
- Independent Review passed;
- Qualification passed/current;
- the current changeset is safe;
- Assurance is complete.

## Inputs

- canonical operation structural-coverage rows supplied by the existing coverage provider;
- an explicitly accepted global debt baseline;
- current operational-operation universe.

Current legacy provider during extraction:

- `public.lf_s36_operation_assurance_coverage_v1()`

Current legacy adapter during extraction:

- `sandbox/lf_contract_gate_test/s36_wp06_ci_completeness_gate.py`

Those historical names are compatibility surfaces only. They must not define the target semantics.

## Applicability

Target owner: `FULL_REGRESSION`.

Applicable:

- explicit Full Regression;
- global audit/reconciliation of operation test coverage;
- controlled migration/cutover validation of the debt baseline itself.

Not applicable:

- ordinary PASE execution merely because a changeset exists;
- Contract Check semantics;
- Independent Review;
- Qualification finalization;
- lifecycle/stateful regression ownership;
- Card-specific E2E ownership.

## Failure classes preserved from the legacy adapter

- `NEW_REQUIRED_OPERATION_DEBT`
- `LIVE_BLOCKED`
- `ACCEPTED_DEBT_STATE_CHANGED_WITHOUT_COVERAGE`
- `BINDING_ACTIVITY_WITHOUT_COVERAGE`
- `NEW_RUN_ACTIVITY_WITHOUT_COVERAGE`

## Migration rule

Do not create a second coverage engine, matrix, baseline store or applicability router.

The extraction sequence is:

1. keep the existing global debt query as the compatibility implementation;
2. freeze this narrower semantic owner;
3. move the carrier only after `FULL_REGRESSION` cutover is authorized/current;
4. retire `S36_ASSURANCE` naming only after consumers read back the new owner;
5. preserve historical S36 artifacts as lineage, not as active ownership.

## EKB

- `S36-ASSURANCE-BOUNDARY-CONTAMINATION-001`
- `TEST-COVERAGE-DEBT-GUARD-SEMANTIC-OVERCLAIM-001`

## Safety

This candidate creates no DB object, workflow, router, registry, writer, coverage engine, baseline store, runtime activation or production behavior.
