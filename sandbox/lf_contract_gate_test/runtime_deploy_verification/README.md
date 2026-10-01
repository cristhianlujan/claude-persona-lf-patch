# RUNTIME_DEPLOY_VERIFICATION_V1

## Purpose

`SADM-PP-L2-014` extracts verification-only runtime/deploy readback from the existing `REFRESCO_RUNTIME_PERFIL_LF` operation.

Flow:

`caller -> ORCHESTRATOR_EXECUTION_GUARD_V1 -> RUNTIME_DEPLOY_VERIFICATION -> exact deploy receipt + exact declared release manifest + health/source/state readbacks -> LF_RUNTIME_DEPLOY_VERIFICATION_RECEIPT_V1`

Without `ORCHESTRATOR_ENTRY_ACCEPTED`, the capability fails closed.

`POST_PASE_ROUTER_V1` is a later consumer (`SADM-PP-L4-019`). This unit does not decide applicability and does not perform deploy.

## Extraction boundary

The existing operation remains the deployment/refresh effect owner. The current operation has an effect step (`runtime_refresh`) followed by readback semantics (`health_readback`, `source_readback`, `state_preservation`) and then mutation/routing/closure responsibilities (`asset_reconcile`, `close`, `report_output`).

This capability keeps only verification semantics and rejects deploy, restart, symlink switch, asset mutation, promotion, rebind and next-gate selection.

EKB anchors:

- `POST-PASE-RUNTIME-DEPLOY-VERIFY-COUPLING-001`
- `POST-PASE-RUNTIME-FULL-REPO-TAR-SCOPE-001`
- `POST-PASE-RUNTIME-HOST-DIAGNOSTIC-IN-DEPLOY-001`

The existing `install.sh` is not changed here. Its full-repository tar and unconditional host diagnostic remain active gaps until their own governed remediation/cutover.

## Exact deployment receipt

The verifier consumes `LF_RUNTIME_DEPLOY_EFFECT_RECEIPT_V1` and cross-binds it to the scope:

- effect operation code;
- deployment execution id;
- target code;
- exact source SHA;
- exact release ref;
- effect applied;
- clean install result;
- deterministic receipt digest.

The verifier never re-enters the deploy operation.

## Required-file manifest

The router/orchestrator declares the exact required release files as relative path + SHA-256 pairs.

The read-only manifest observation must match the declared set exactly. Missing files, undeclared extra files or hash mismatches fail closed. This prevents whole-repository transport from silently becoming the verification authority.

## Readbacks

Three normalized read-only observations are required:

1. release manifest;
2. service health + runtime endpoint source SHA;
3. preserved lifecycle/operational/automatic-impact state.

Every observation requires `read_only=true`, `mutation_performed=false` and a deterministic digest.

## Receipt

`LF_RUNTIME_DEPLOY_VERIFICATION_RECEIPT_V1` returns `VERIFICATION_VERIFIED` only when deployment receipt, exact manifest, health/source and state all match.

It explicitly records zero deploy, restart, symlink switch, asset mutation, promotion and next-gate selection by the verifier.

## Test

`python sandbox/lf_contract_gate_test/runtime_deploy_verification/test_runtime_deploy_verification_v1.py`

Expected:

`PASS_RUNTIME_DEPLOY_VERIFICATION_V1 checks=19`

The matrix covers guarded entry, scope digest, path safety/duplicates, effect receipt cross-binds and tampering, missing/extra/hash-drift manifest files, read-only enforcement, unhealthy service, runtime source mismatch, state drift, routing contamination and mutation attempts.

## Materialization state

Source candidate only. The registry projection is included for later governed application/readback but is not applied by this unit.

No deploy, Supabase projection apply, owner-runner cutover, runtime activation, production activation, installer change or legacy retirement is authorized here.
