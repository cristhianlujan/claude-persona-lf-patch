# PASE_MERGE_GATE_CARRIER_V1

## Purpose

Run `PASE_MERGE_GATE_V1` from trusted base-branch code, independently of candidate code, and consume canonical exact-head qualification for control-system candidates.

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
 public.lf_qualification_receipts                  |
 CONTROL_SYSTEM exact-head receipt                 |
 via lf_control_system_qualification_readback_v1   |
             |                                     |
             +-- exact candidate/base/repository   |
             +-- canonical source execution        |
             +-- trusted-base validator recheck    |
             |                                     |
             +------------------+------------------+
                                v
                       PASE_MERGE_GATE_V1
```

## Qualification readback

A control-system candidate cannot self-authorize a PASS. The carrier asks the canonical database function `lf_control_system_qualification_readback_v1(candidate_id, repository, base_sha, head_sha)` for the current exact-head receipt.

The readback must be `QUALIFIED`, match exact candidate/repository/base/head, identify `PASE_CONTROL_QUALIFICATION_V1`, carry a trusted validator revision and source execution, and return the stored qualification input/result. The carrier then re-runs the trusted-base Python `PASE_CONTROL_QUALIFICATION_V1` validator over those exact bytes. Only `CANDIDATE_QUALIFIED` reaches merge policy.

No exact receipt returns `MISSING` and blocks. Stale base/head, candidate/repository drift, malformed payload, invalid validator revision or non-qualified result also block fail-closed.

## Trust boundary

The workflow checks out exactly `github.event.pull_request.base.sha`. Candidate objects are fetched only so trusted base code can compute the Git diff. Candidate workflows, Python modules, build hooks and package code are never executed by this carrier.

The Supabase database password is exposed only to trusted base code in the `pull_request_target` job. The carrier performs readback only and does not mutate qualification receipts, rulesets, bindings, controls or production state.

## Behavior

- ordinary `EXECUTION_PLAN` changes pass only when repair enforcement has no active blocker lacking canonical evidence;
- control-system changes without exact canonical qualification block;
- qualified control-system changes can pass only after trusted-base revalidation;
- active blocker without canonical exact-head PASS evidence blocks;
- stale base, repository drift, head drift or malformed canonical plan blocks.

## Enforcement boundary

The carrier result keeps `external_enforcement_active=false`; the carrier does not own the GitHub ruleset. During bootstrap repair the required status remains outside external enforcement. It can be restored only after independent live PASS/BLOCK proof and ruleset readback.

## Self-test

```bash
python3 sandbox/lf_contract_gate_test/pase_merge_gate/pase_merge_gate_carrier_v1.py self-test
```

The self-test proves normal PASS, missing-qualification BLOCK, canonical qualification PASS, qualification head drift BLOCK, active-control evidence BLOCK and stale-base BLOCK.
