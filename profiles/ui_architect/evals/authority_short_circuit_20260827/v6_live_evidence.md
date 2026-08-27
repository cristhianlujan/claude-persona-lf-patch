# UI Architect authority short-circuit remediation V6 — live evidence

Status: CANDIDATE / LIVE_RUNTIME_RETEST_REQUIRED

## Governance binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260827-005`
- Asset: `PERFIL-UI-ARCHITECT`
- Original V5 baseline main: `f06607b270e7f543dc2ff3674dc6fc2f540805b4`
- Reconciled main baseline: `92908a1d1b282e3c564594dd7bfb556f51c88a37`
- Candidate branch: `lf/ui-architect-authority-short-circuit-v6-20260827`

## Demonstrated live failure after V5
Runtime request `b2ee6683-cf50-41b2-ba74-3cab1b106040` executed from `main@f06607b270e7f543dc2ff3674dc6fc2f540805b4` with the pinned zero-cost Qwen2.5-VL 3B runtime.

The input explicitly established upstream authority: `Resumen` was the only canonical payable-amount source and the top strip was redundant. The correct behavior therefore was to consume that resolved context and remediate the redundant presentation without asking which source should survive.

Observed RAW instead returned `BLOCKED` with missing input `authoritative survivor for duplicated presentation` and `pipeline_action: BLOCK_PIPELINE`. This preserved V3 directionality safety but violated V5 context resolution by ignoring authority already supplied in the same execution context.

## V6 minimal patch
The first runtime gate now resolves authority before any blocking branch:
- explicit supplied/upstream authority sets `authority_resolved=true` and identifies survivor/redundant presentation;
- when `authority_resolved=true`, blocking for an unknown survivor is explicitly forbidden;
- generic `A canonical; B redundant` must become `KEEP A` + `REMOVE/HIDE/MERGE B`;
- `BLOCK_PIPELINE` is legal only when authority remains unresolved after supplied/upstream context and visible hierarchy are considered;
- the V3 anti-amplification rule remains unchanged.

## Reconciliation on latest main
PR #252 first passed its checks against an older base, but concurrent merges advanced `main`. GitHub then correctly reported the required `lf-contract-check` as expected for the current base. Following the same reconciliation pattern used by prior UI work, the candidate branch was reset to current `main@92908a1d1b282e3c564594dd7bfb556f51c88a37` and only the V6 profile-local files were reapplied. New governance changes from main are preserved.

## Closure gate
After merge, rerun both live properties:
1. resolved-authority case: must not block for unknown survivor; must preserve the explicitly canonical source and reduce duplication;
2. unresolved-authority case: must remain fail-closed and return `BLOCK_PIPELINE` rather than guess.

No runtime/provider/model change is authorized by this remediation.
