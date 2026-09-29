# PASE GitHub EntryPoint V1

## Scope

This closes the remaining **parallel ordinary pull-request entrypoints** while the PASE repair window is active.

The repository may keep operational or independently trusted workflows, but normal PR validation enters through exactly one workflow:

```text
pull_request
    |
    v
.github/workflows/lf-contract-check.yml   # compatibility path/name, temporary
    |
    v
Changeset Governance / lf-ci-execution-plan/v2
    |
    v
PASE repair enforcement
```

The historical `lf-contract-check` identity is intentionally retained in this phase because live consumers still bind its workflow name/path. Renaming it to `pase.yml` is a later coordinated identity cutover after those consumers and live authority are migrated.

## Authority ordering

The compatibility entrypoint MUST NOT run the historical `scripts/lf_contract_check.py` sandbox-scope validator before Changeset Governance.

Repository-path admission is a Changeset Governance precondition implemented by `lf_changeset_governance.py`; change-family classification and applicability then produce the canonical execution plan. A legacy Contract Check allowlist must not pre-empt a path that Changeset Governance already recognizes and routes to its real owner.

Therefore the entrypoint order is:

```text
exact candidate checkout
  -> single-entrypoint invariant
  -> Changeset Governance / canonical applicability plan
  -> PASE Orchestrator dispatch plan
  -> repair-window enforcement
  -> evidence persistence
```

Unknown or unauthorized repository changes remain fail-closed through Changeset Governance; removing the legacy pre-applicability validator does not create an allow-all path.

## Allowed workflow classes during repair

### 1. Ordinary PR entrypoint

Exactly one:

- `.github/workflows/lf-contract-check.yml` — current PASE entrypoint under compatibility identity.

It owns GitHub transport, exact candidate context, canonical applicability-plan emission, repair-enforcement boundary and evidence persistence. It does not execute legacy domain controls automatically while they are `REPAIR_OBSERVE_ONLY`.

### 2. Independent trusted PR guardians

The following use `pull_request_target` and trusted base code:

- `.github/workflows/lf-github-reconcile-v3.yml` — independent self-change/reconciliation boundary;
- `.github/workflows/pase-merge-gate.yml` — independent merge-decision carrier.

They are not ordinary candidate-controlled domain-control routers.

### 3. Operational workflows

Operational events may remain when they are not ordinary PR validators, including currentness evaluation, evidence workers and governed owner brokers.

## PR regressions retired in the earlier cutover

The earlier PASE cutover removed parallel automatic PR execution from legacy validator workflows. Their underlying validators/tests were not deleted; during the repair window they remain diagnostic source material and may return to blocking execution only through canonical applicability plus qualified owner-runner cutover.

## Deferred identity cutover

This phase still does not rename `.github/workflows/lf-contract-check.yml` because current consumers bind the legacy identity, including reconciliation and the P0 exact-head evidence broker. Those consumers must be migrated first, then `pase.yml` can become the active identity with post-cutover exact-head readback.

## Deterministic proof

```bash
python3 sandbox/lf_contract_gate_test/pase_github_entrypoint/test_single_pr_entrypoint_v1.py
```

The proof requires one ordinary PR entrypoint and forbids reintroduction of the legacy Contract Check structural-admission step ahead of Changeset Governance.
