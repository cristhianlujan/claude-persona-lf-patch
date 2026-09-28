# PASE_MERGE_GATE_V1

## Purpose

`PASE_MERGE_GATE_V1` is the neutral merge-policy evaluator that should eventually sit between the authoritative PASE/Changeset Governance decision and the repository required-status rule.

It is intentionally **not** a replacement Router, Contract Check, qualification engine, domain control, or GitHub ruleset manager.

```text
Changeset Governance / lf-ci-execution-plan/v2
                  |
                  +--> authoritative merge route
                  |
                  v
          PASE_MERGE_GATE_V1
           /              \
CONTROL_SYSTEM_QUALIFICATION  EXECUTION_PLAN
        |                         |
qualified evidence          applicable control results
        |                         |
        +-----------+-------------+
                    v
                 PASS/BLOCK
```

## Authority boundary

The gate does not decide which route applies.

It requires `lf-pase-merge-route/v1` with:

- `authority = CHANGESET_GOVERNANCE_LF_V1`;
- exact candidate `head_sha`;
- source `source_revision`;
- one of `CONTROL_SYSTEM_QUALIFICATION | EXECUTION_PLAN`;
- the exact control IDs that remain mandatory for that merge route.

The route is an **input from the existing Changeset Governance authority**. This candidate does not yet materialize that route upstream and does not infer it from changed paths.

## CONTROL_SYSTEM_QUALIFICATION

For a control-system candidate, the route may select independent qualification instead of treating a contaminated legacy carrier as the candidate's verdict authority.

The gate requires an independently validated `PASE_CONTROL_QUALIFICATION_V1` result:

- exact same `head_sha`;
- exact candidate ID declared by the route;
- `verdict = CANDIDATE_QUALIFIED`;
- `qualified_only = true`;
- activation/cutover/rebind/legacy-retirement authorizations remain `false`;
- result digest matches exactly;
- evidence envelope declares independent validation and validator revision.

Any additional controls that must still pass are declared by Changeset Governance in `required_control_ids` and are enforced exactly. The merge gate itself never chooses which legacy or domain controls to suppress or preserve.

## EXECUTION_PLAN

For a normal change:

- route control IDs must equal `plan.required_controls`;
- every required control must appear exactly once;
- exact head must match;
- each result must be `PASS`;
- missing, extra, duplicate, failed, or head-drifted evidence blocks.

## Trust boundary

The pure Python evaluator validates policy shape and exact identity. It is **not** the trust root for GitHub artifacts.

A future workflow/carrier must obtain:

1. the merge route from the protected Changeset Governance/execution-plan surface;
2. qualification evidence from the independent qualification surface;
3. control results from their canonical execution evidence.

Candidate-owned files must never be accepted as authoritative merely because they have the right JSON shape.

## #1170 regression

The deterministic regression includes `PASE_ORCHESTRATOR_V1` / PR #1170 as the first qualification-route fixture.

That proves only the gate semantics: when Changeset Governance explicitly selects `CONTROL_SYSTEM_QUALIFICATION`, a canonical exact-head `CANDIDATE_QUALIFIED` result is sufficient, plus any explicitly preserved controls. The merge gate does not repair E16, Profile Runtime, S36, Migration, Contract Check, Validate Packs, or DB Regression.

## Current integration gap

Current `lf-ci-execution-plan/v2` on `main` does **not yet** emit `lf-pase-merge-route/v1`.

Therefore this PR is a repository candidate only. It is not ready to replace `lf-contract-check` in `protect-main` until a separate qualified upstream handoff and a merge-gate workflow/carrier are proven.

## Non-scope

This candidate does not:

- modify `.github/workflows/*`;
- modify `protect-main` or any ruleset;
- merge #1170;
- reclassify changed paths/applicability;
- execute domain controls;
- qualify candidates itself;
- mutate Supabase/live authority;
- activate, cut over, rebind, retire legacy, deploy, or touch production.

## Test

```bash
python3 sandbox/lf_contract_gate_test/pase_merge_gate/test_pase_merge_gate_v1.py
```

Expected marker:

```text
PASS_PASE_MERGE_GATE_V1 checks=19
```
