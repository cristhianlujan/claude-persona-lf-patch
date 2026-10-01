# GITHUB_RECONCILIATION_V1

## Purpose

`SADM-PP-L2-012` extracts the deterministic post-merge part of legacy **LF GitHub Reconciliation V3** into a bounded transversal capability.

The capability does not decide applicability. It consumes an already-declared reconciliation scope and returns a typed receipt.

Flow:

`POST_PASE_ROUTER_V1 scope -> ORCHESTRATOR_ENTRY_GUARD -> GITHUB_RECONCILIATION -> LF_GITHUB_RECONCILIATION_RECEIPT_V1`

`POST_PASE_ROUTER_V1` is a later consumer unit (`SADM-PP-L4-019`), so this candidate defines only the capability-specific scope interface; it does not invent a global POST_PASE_PLAN authority.

## What is reused

Legacy sources were used as evidence of proven checks:

- `.github/workflows/lf-github-reconcile-v3.yml`
- `supabase/functions/lf-github-reconcile-v3/index.ts`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_applicability.py`

The extracted capability preserves exact-merge/source/file readback semantics but removes responsibilities that belong elsewhere.

## Boundary cleanup

Existing EKB findings are authoritative:

- `POST-PASE-RECONCILIATION-PREMERGE-ADMISSION-CONTAMINATION-001`
- `POST-PASE-RECONCILIATION-GLOBAL-FILE-SCOPE-001`

Therefore this capability explicitly forbids:

- `pull_request_target` / pre-merge self-change admission;
- independent applicability calculation;
- repository-wide inventory enumeration;
- global `git ls-files` manifest consumption;
- unconditional governance bundle enumeration;
- evidence persistence / gate recording;
- artifact promotion;
- deploy/runtime/production mutation.

Those legacy behaviors remain untouched until a later authorized cutover. This unit creates the clean capability source only.

## Input scope

`LF_GITHUB_RECONCILIATION_SCOPE_V1` contains:

- repository + target branch;
- plan digest;
- expected merge commit SHA;
- exact `declared_paths` only (`CHANGED` or explicitly named `ANCHOR`);
- named repository invariants, when required;
- deterministic `scope_digest`.

Undeclared file evidence is a failure, not an invitation to widen scope.

## Carrier observations

The carrier resolves GitHub facts; the deterministic capability validates them:

- successful source workflow on `main` bound to the expected merge SHA;
- merged PR bound to the same SHA;
- current `main` head bound to the same SHA;
- sha256 + git blob + commit SHA for each declared path;
- only the named repository invariants.

The validator performs no network calls and no writes.

## Receipt

`LF_GITHUB_RECONCILIATION_RECEIPT_V1` emits:

- `RECONCILED`, `ready=true` only when all declared evidence matches;
- `RECONCILIATION_FAILED`, `ready=false` otherwise;
- failures are typed and path-scoped;
- receipt includes deterministic digest.

The receipt is evidence. It cannot promote an artifact, materialize the next gate, or authorize downstream execution by itself.

## Test

`python sandbox/lf_contract_gate_test/github_reconciliation/test_github_reconciliation_v1.py`

Expected: `PASS_GITHUB_RECONCILIATION_V1 checks=12`.

The final positive test proves a one-file bounded scope can reconcile successfully without a global inventory or unrelated governance bundle.

## Materialization state

Source candidate only. No Supabase apply, owner-runner cutover, runtime activation or production activation is authorized by this unit.
