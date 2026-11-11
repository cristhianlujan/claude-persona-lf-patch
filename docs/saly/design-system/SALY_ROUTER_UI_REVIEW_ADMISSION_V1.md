# SALY_DS_V1 — Router/UI review boundary assessment

**Status:** CANDIDATE / PRE-ADMISSION / NO_GO  
**Issue:** #3714  
**Scope:** Allow only a future, governed read-only review of `SALY_DS_V1` by `PERFIL-UI-ARCHITECT`. No production activation, no SALY-wide business enablement.

## Verified baseline (2026-11-09)
- Business catalog: `LF=ENABLED`, `SALY=RECOGNIZED_NOT_ENABLED`.
- Live router `lf_router_route_v1` MD5: `8a74d20e7ad65f1fb3f80f1cc4bbb313`.
- Existing governed router maintenance operation: `ACTUALIZACION_ROUTER_LF` (five active steps: baseline, sandbox, patch, regression, close).
- `EJECUCION_PERFIL_LF` is registered ACTIVE, read-only; `PERFIL-UI-ARCHITECT` is a candidate read-only profile with DESIGN_TOKENS, COMPONENT_DESIGN, VISUAL_DEFINITION capabilities CURRENT.
- Live read-only preflight output: four known guards (4/4) detected, and no effects performed.

## Four independent business guards
1. `public.lf_router_route_v1`: checks business status `ENABLED`; SALY ends `BUSINESS_NOT_ENABLED`.
2. `public.lf_router_profile_after_selection_v1`: checks `negocio_codigo='LF'`.
3. `public.lf_router_profile_execution_handoff_v1`: checks `business='LF'`.
4. `public.lf_router_profile_execution_handoff_validate_v1`: checks `handoff.business='LF'`.

All four must retain LF behavior and fail closed for any unauthorized SALY request. **Do not patch just the first guard.** Changing the SALY catalog row to `ENABLED` is explicitly forbidden in this scope.

## Authority criteria before any patch
The existing system must attest the *server-owned* tuple:
`business=SALY`, `operation=EJECUCION_PERFIL_LF`, `profile=PERFIL-UI-ARCHITECT`, `asset=SALY_DS_V1`, `intent=REVIEW`, `effect=READ_ONLY`.

Neither `Stage1.negocio_codigo`, a name in `target_hint`, nor a forged `p_caller` object qualifies as authority. Reuse existing profile-owned OIDC/Edge transport and existing operation governance; do not introduce a second router, bypass Gate2 or broaden other SALY capabilities.

**Open architecture blocker:** no verified server-owned, per-business/target permission policy or caller receipt for the exact SALY review tuple was established. The existing governed callers inventory contained only a PROFILE_UPDATE caller. Without one, do not write a speculative permit rule.

## Files
- `saly_router_preflight_read_only.sql`: runnable SELECT-only diagnostic, not an activation test.
- Candidate design-source files are now versioned under `docs/saly/design-system/candidate/` in this DRAFT PR. Exact Git blob readback: `design_system.json` = `551469ed451f60af43e874c4688451a210a82dc1` (source SHA256 `2967f2e3cbdc6d4651ffd877a05fdd6c3377266561e522e22e315fe8e64096d5`) and `ESPECIFICACION_SALY_DS_V1.md` = `12549166fe48450a405d62d4bbed58bb694a1ec9`. Both match the original source blobs byte-for-byte. The visual screenshot `evidencia_home_visual_aprobado.png` (SHA256 `b2d355bf2d1cf0e4614a0ecd21e837346eb5fe59234fda70c4cd6e7fc10cde7a`) remains outside GitHub; visual review must acknowledge that dependency.

## Required next governed steps
1. Bind source/currentness and a narrowly authorized service-owned SALY review tuple in existing governance. Inspect related contracts, don't guess.
2. Use `ACTUALIZACION_ROUTER_LF` for minimal reversible patch and exact-head baseline, under its real admission.
3. Execute canaries for all four function guards, LF unchanged, SALY exact review permitted, SALY nonreview denied; reject spoofed Stage1/caller and multibusiness.
4. Verify runner-owned new execution ID via GitHub OIDC/Edge, actual `PERFIL-UI-ARCHITECT` output, semantic/structural verdict and readback.
5. Keep Design System in CANDIDATE until visual values, contrast and tokens are validated and registered under SALY authority.

**Completion status:** NO_GO / PATCH_NOT_EXECUTED / UI_PROFILE_NOT_EXECUTED. Only safe read-only diagnostics and draft evidence prepared.
