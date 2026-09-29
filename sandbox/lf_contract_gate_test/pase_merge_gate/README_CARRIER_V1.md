# PASE_MERGE_GATE_CARRIER_V1

## Purpose

Run `PASE_MERGE_GATE_V1` from trusted base-branch code, independently of candidate code.

```text
pull_request_target
      |
      v
trusted PR base checkout
      |
      +-- resolve current main == event base
      +-- fetch candidate Git objects only
      +-- do NOT checkout/import/execute candidate code
      |
      v
CHANGESET_GOVERNANCE_LF_V1
  emit lf-ci-execution-plan/v2
      |
      v
PASE_MERGE_ROUTE_V1
      |
      +-- EXECUTION_PLAN --------------------------+
      |                                            |
      +-- CONTROL_SYSTEM_QUALIFICATION             |
             |                                     |
             v                                     |
       canonical LF operation ledger               |
       GITHUB_CONTRACT_GATE_LF                     |
       target_type=PASE_CONTROL_QUALIFICATION      |
             |                                     |
             +-- exact candidate/base/repo         |
             +-- COMPLETED + zero blockers         |
             +-- contract_judge/report_output PASS |
             +-- trusted-base validator recheck    |
             |                                     |
             +------------------+------------------+
                                v
                       PASE_MERGE_GATE_V1
```

## Qualification readback

A control-system candidate is never allowed to provide its own authoritative PASS. The independent qualifier persists its assessment in the existing canonical LF operation ledger using `GITHUB_CONTRACT_GATE_LF` with:

- `target_type = PASE_CONTROL_QUALIFICATION`;
- `target_code = <candidate_id>`;
- exact repository, base SHA and candidate head;
- `qualification_authority = PASE_CONTROL_QUALIFICATION_V1`;
- `independent_qualifier = true`;
- canonical `qualification_input` and `qualification_result` in the execution manifest.

The trusted carrier requires exactly one matching completed execution, zero canonical blockers, PASS terminal `contract_judge` and `report_output` steps, then re-runs the trusted-base `PASE_CONTROL_QUALIFICATION_V1` validator over that exact input/result. Only `CANDIDATE_QUALIFIED` can reach the merge policy.

Persisting a record does not itself make it valid: stale base/head, candidate/repository drift, duplicate records, incomplete operation state, missing terminal evidence, invalid qualification shape/verdict or any canonical blocker all fail closed.

## Trust boundary

The workflow checks out exactly `github.event.pull_request.base.sha`. Candidate objects are fetched only so trusted base code can compute the Git diff. Candidate workflows, Python modules, build hooks and package code are never executed by this carrier.

The database password is exposed only to trusted base code in the `pull_request_target` job. Candidate code is not checked out or executed in that context. The carrier performs readback only; it does not mutate qualification records, GitHub rulesets, Supabase state, bindings, controls or production state.

## Behavior

- ordinary `EXECUTION_PLAN` changes pass only when the repair-enforcement projection has no active blocker requiring missing evidence;
- a control-system change without independent canonical qualification blocks;
- the same control-system change can pass only after exact-head qualification is independently persisted and revalidated;
- an active blocker without canonical exact-head PASS evidence blocks;
- stale base, repository drift, head drift or malformed canonical plan blocks.

## Enforcement boundary

The carrier result retains `external_enforcement_active=false` because the carrier itself does not own the GitHub ruleset. External enforcement is a repository setting and is validated separately. During bootstrap repair the required status may be temporarily removed; after live PASS/BLOCK proof the same `pase-merge-gate` status can be restored as the only required PASE merge status.

## Self-test

```bash
python3 sandbox/lf_contract_gate_test/pase_merge_gate/pase_merge_gate_carrier_v1.py self-test
```

The self-test proves normal PASS, missing-qualification BLOCK, canonical qualification PASS, qualification head drift BLOCK, active-control evidence BLOCK and stale-base BLOCK.
