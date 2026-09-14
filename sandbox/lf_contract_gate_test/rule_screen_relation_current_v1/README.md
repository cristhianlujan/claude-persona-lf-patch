# Rule ↔ Screen Relation — Current-State Regression V1

## Purpose

Provide a clean, exclusive regression harness for the **current canonical** `VINCULACION_REGLA_PANTALLA_LF` capability already present on `main`.

This lane does not recreate, promote, bind, or modify the capability. It only verifies the current governed contract and exercises one transactional canary that is fully rolled back.

## Source boundary

Branch was created directly from:

`main@f56a1b5b3e094f603adafd16038ccd6c96b04ca5`

That base already contains the durable capability, its ACT-0001 controlled-production integration, and Strategy Update migration-source parity restored by PR #764.

The PR for this lane must remain exclusive to:

- `sandbox/lf_contract_gate_test/rule_screen_relation_current_v1/README.md`
- `sandbox/lf_contract_gate_test/rule_screen_relation_current_v1/rule_screen_relation_current_rollback_canary_v1.sql`
- `sandbox/lf_contract_gate_test/rule_screen_relation_current_v1/current_lane_manifest_v1.json`

No migrations, workflow changes, shared validators, Router patches, production state changes, S26/S30/S31 assets, or unrelated producer files belong in this PR.

## Expected canonical state

The regression harness requires, without changing them:

- operation `VINCULACION_REGLA_PANTALLA_LF` exists;
- operation registry status is `PRODUCCION_CONTROLADA`;
- exactly one `ACTIVE_ENFORCEMENT` contract exists and it is `CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0`;
- Router binding `REGLA_PANTALLA_RELATION + REGLA_PANTALLA_LINK` is `ACTIVE` with `write_allowed=true`;
- helper `public.lf_regla_pantalla_link_v1(text,text,integer,text)` exists;
- helper contains no `DELETE FROM lf_ops.reglas_pantallas` path;
- helper continues to accept observed rule states `CANDIDATO` and `VIGENTE` through the governed relation operation.

The exact active-contract identity above is sourced from live readback. An earlier candidate lane encoded `CONTRACT-VINCULACION-REGLA-PANTALLA_LF-v1.1.0`; its rollback preflight correctly failed against current live state and that stale spelling is not reused.

## Canary boundary

The SQL bundle runs inside `BEGIN/ROLLBACK` and:

1. reads and validates canonical operation/contract/router state;
2. selects an existing rule/screen pair with no current relation;
3. snapshots the rule and screen;
4. inserts a temporary governed execution row bound to that exact pair;
5. calls the existing canonical helper;
6. replays the same call and requires exact cardinality `1`;
7. proves rule and screen remained unchanged;
8. verifies missing-rule and missing-screen paths block fail-closed;
9. rolls back the transaction;
10. leaves no durable execution or relation residue.

## Non-goals

This PR does **not**:

- materialize a second operation;
- create or update any migration;
- modify the production contract;
- modify ACT-0001 or Router bindings;
- activate runtime;
- authorize Golden;
- change business logic;
- claim a new production promotion.

PR #748 remains historical evidence only. PR #763 became stale after the independently owned #764 base advance. PR #765 was discarded after its exact rollback preflight exposed the stale contract-code spelling. This lane is the clean replacement built from the same current `main`, with that currentness defect corrected before merge.