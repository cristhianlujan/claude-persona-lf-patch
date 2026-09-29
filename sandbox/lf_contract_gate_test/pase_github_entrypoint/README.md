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

The historical `lf-contract-check` identity is intentionally retained in this phase because live consumers still bind its workflow name/path. Renaming it to `pase.yml` is a later coordinated cutover after those consumers and live authority are migrated.

## Allowed workflow classes during repair

### 1. Ordinary PR entrypoint

Exactly one:

- `.github/workflows/lf-contract-check.yml` — current PASE entrypoint under compatibility identity.

It owns GitHub transport, exact candidate context, structural admission, canonical applicability-plan emission, repair-enforcement boundary and evidence persistence. It does not execute legacy domain controls automatically while they are `REPAIR_OBSERVE_ONLY`.

### 2. Independent trusted PR guardian

Exactly one exception uses `pull_request_target`:

- `.github/workflows/lf-github-reconcile-v3.yml`.

This is deliberately not folded into candidate-controlled PASE execution because it validates self-change admission from trusted base context. It is an anti-self-approval boundary, not a second domain-control router.

### 3. Operational workflows

Operational events may remain when they are not ordinary PR validators:

- `lf-material-currentness.yml`: `workflow_dispatch` / `workflow_call` currentness evaluation;
- `story-agent-evidence-verifier.yml`: main-push OIDC evidence worker;
- `profile-driven-screen-generation.yml`: owner-only S30 `issue_comment` write broker;
- `lf-customer-profile-creator-governance-caller.yml`: governed branch/dispatch operation;
- `asset-smoke-test.yml`: scoped push smoke test.

## PR regressions retired in this phase

The following automatic PR jobs are removed from their workflows:

- Currentness Authority regression job;
- Profile Driven Screen Generation deterministic contract gate;
- Story Agent semantic-mini-judge regressions;
- Story Agent runtime-optimization regressions.

Their underlying validators/tests are **not deleted**. During the repair window they remain diagnostic source material and can only return to automatic blocking execution through the canonical PASE applicability + qualified owner-runner cutover.

This prevents a workflow path filter from pre-empting Changeset Governance and prevents a parallel workflow from becoming an accidental merge authority.

## Deferred identity cutover

This phase does not rename `.github/workflows/lf-contract-check.yml` because current repository/live consumers still bind the legacy identity, including:

- `lf-github-reconcile-v3.yml` workflow-run subscription;
- the P0 exact-head evidence broker policy workflow name/path;
- live repository-governance authority readback.

The final rename requires a coordinated consumer + authority migration and post-cutover exact-head readback.

## Separate finding, not repaired here

The retained S30 ChatOps broker still expects the historical check name `Run LF pack validators` together with `lf-contract-check`. `validate-lf-packs.yml` has already been retired, so that dependency is a separate stale-contract finding. It is intentionally not patched in this solution.

## Deterministic proof

```bash
python3 sandbox/lf_contract_gate_test/pase_github_entrypoint/test_single_pr_entrypoint_v1.py
```

Expected marker:

```text
PASS_PASE_SINGLE_PR_ENTRYPOINT_V1 workflow_count=7 ordinary_pr=lf-contract-check.yml independent_guardian=lf-github-reconcile-v3.yml
```
