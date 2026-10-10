# Analysis A7→A9 — B2B_APP_SHELL refresh: verified read-only preflight

**Scope**: Programming Agent Analysis only; not Input Governance. **Mode**: `READ_ONLY_SOURCE_CURRENTNESS_PREFLIGHT`.
**Status**: `REFRESH_REQUIRED / SNAPSHOT_NOT_ADMISSIBLE`. This is an evidence report, **not** a new Analysis snapshot, signed currentness receipt, PG-01 admission, or model-inference result.
**Date**: 2026-10-09. **Base**: LF Supabase sandbox `mhwmirqcgxxukpctffuv`, GitHub `cristhianlujan/libertad-financiera` main. No mutation of source tables, production, or append-only context store.

## EKB preflight

Active and applicable: `PROGRAMMING-ANALYSIS-CONTEXT-SNAPSHOT-HANDOFF-001`, `PROGRAMMING-ANALYSIS-MATERIAL-FRONT-COVERAGE-001`, `PROGRAMMING-ANALYSIS-SCOPE-FRONT-CONSISTENCY-001`, `PROGRAMMING-ANALYSIS-A14-EVIDENCE-TIER-FALSE-READY-001`. Do not add parallel currentness/selector/receipt engines.

## Source and authority readbacks

| Evidence | Historical Analysis context | Observed live source | Required action |
|---|---|---|---|
| Shell authority | `B2B_APP_SHELL@v0.9` | `lf_ops.app_shells@v1.0`, `CANDIDATO`, updated 2026-10-07 22:33:42 UTC | Re-evaluate material delta and authoritative status; never silently promote candidate |
| Source repo | `e3a116db67ff4637fdd6dee4fee150b96a4d959d` | `994bda4aac4f92ea40531a2e84fdad6765397e84`, 14 commits ahead | Reconcile exact changed source files, implementation state and impact |
| Shell state rule | historical ref `B2B-RULE-SHELL-STATE-001` | `CANDIDATO`, updated at same time as shell v1.0 | Re-evaluate scope-bound rules |
| Screens | prior frozen | 58 total in `lf_ops.pantallas`; none modified after the historical receipt timestamp in that table | Preserve unaffected evidence only after currentness verification |
| Support | old S07 blocker said table absent | `lf_ops.soporte_canales` and `lf_ops.b2b_support_channels('USER_SUPPORT')` exist; 3 active, 3 resolver rows | Remove obsolete *absence* hypothesis; verify authenticated consumer, authorized purpose and business correctness |
| Session | old S05 blocker said implementation absent | `src/lib/b2b/session-context.ts` and `lf_ops.b2b_current_user_id` / `b2b_current_company_id` exist | Requires authenticated runtime evidence; mere existence does not prove functional completion |
| Effective permissions | old S08 BLOCKED | `src/app/b2b/(portal)/layout.tsx` passes session and support but no `effectivePermissionCodes`; shell explicitly fail-closed | Keep S08 BLOCKED |
| Super-admin group selector | old S06 BLOCKED | No verified, effective group→company authorization path in this preflight | Keep S06 BLOCKED / verify separately before advancing |

**Historical context**: `38a8f5c8-a6f3-45d6-b1ee-823af130e647`, original context hash `5ed3ffd513e4caadc65a9cbfb5991b6f8caeac8f714bec2c95fab23849a16e10`, `PARTIAL_READY` with 9 scopes (5 previously READY), 10 *abbreviated* fronts, 0 matrix rows. It is immutable; do not change or rewrite it. A read-only join derives 15 scope/front references with 0 unknown front refs and 0 old `READY`→`BLOCKED` pairs. Derivability **does not imply currentness**.

**Canonical A7 gap**: historical `material_front_coverage.fronts[]` only has abbreviated `id/kind/status/closure` fields. Missing canonical `material_fronts[].front_id`, `scope_refs`, evidence/currentness, blockers and coverage fingerprint. Material front completeness must be obtained from A4/A6/A7 source evidence. Neither invented evidence nor an old `READY` flag can fill missing proof. A9 assembler now rejects abbreviated fronts, enforces bidirectional map, and can produce matrix only when canonical full A7 is available.

## Per-scope provisional delta classification

| Scope | Previous | Refresh preflight (NOT qualified admission) |
|---|---|---|
| S01 SHELL_FRAME | READY | Code exists; recertify v1.0/currentness |
| S02 NAVIGATION_AND_PLACEHOLDERS | READY | Code exists; recertify affected shell state rule and currentness |
| S03 DESIGN_AND_ASSETS | READY | Code/assets exist; verify canonical tokens and revision |
| S04 TOPBAR_PRESENTATION | READY | Code exists; verify changed authority and rule |
| S05 B2B_SESSION_COMPANY_BINDING | BLOCKED absence | Partial source implementation now exists; need real authenticated user→company receipt; do not declare READY |
| S06 SUPERADMIN_GROUP_SELECTOR | BLOCKED | Still lacks verified governing group→company authority/readback |
| S07 SUPPORT_CONTACT_RUNTIME | BLOCKED absence | Governing table/RPC and code now exist; verify live authenticated path before readiness |
| S08 PERMISSION_RUNTIME_BINDING | BLOCKED | Still no effective permissions passed to operational shell; BLOCKED |
| S09 RESPONSIVE_A11Y | READY | Code exists; recertify revision/currentness and QA boundary |

No actual Analysis stage, model producer, or PG-01 runtime consumer ran. This document does **not** change ledger percentage or historic scope dispositions.

## Exact source-only test readback

On authorized `scalora-vps`, exact Draft PR #2071 head `5b8ed70384bafc50fa8ac779cc10238354b5d82c`:
- `validate_wave1_boundary_contracts_v1.py --self-test`: PASS; existing 99 negative checks.
- `test_analysis_evidence_boundary_v1.py`: PASS; false READY, missing/malformed digest, duplicate/contradictory/wrong-scope fronts, forged provider and model claims.
- `test_analysis_pg01_snapshot_payload_v1.py`: PASS; valid synthetic canonical A7→A9 assembly, two assembly negatives, 14 payload negatives.
- This is **contract-level proof only**; no actual LLM/provider receipt, no independently judged inference, no real PG-01 E2E.

## Required next execution, fail-closed

1. A3/A4/A6 currentness and impact resolver: bind exact live authority revision, repo state, changed rule, existing functions and persisted context. Reuse unchanged evidence; `CANDIDATO` is not assumed `VIGENTE`.
2. A7 recomputes FULL canonical material-front coverage using existing EKB/authority/currentness references. Unproven evidence must become affected `NEED_MORE_EVIDENCE`/BLOCKED, not synthetic source refs.
3. A9 assembles bidirectional `scope_front_matrix[]`, applies `validate_programming_snapshot_payload_v1`, checks source/authority fingerprint and lossless snapshot. Readiness for changed scopes is re-evaluated; unaffected scopes preserve proofs only if still current.
4. A9 may persist a **new** `DECISION_CONTEXT_ASOF` version only with authorized actor and verified current source/material proof. Never mutate old history. PG-01 independently resolves the exact receipt and executes real consumer/readback qualification.
5. A14 model inference / independent oracle is separate; deterministic Python replay does not qualify it.

Current safe disposition: **do not perform an ungrounded refresh-to-READY or merge**. Keep source recorders operating normally.
