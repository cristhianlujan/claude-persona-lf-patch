# PATCH_SECURITY_ROUTER_REJECT_PARTIAL_SCOPE_CREATION_LF_v0.1

Status: CONTROLLED_SECURITY_PATCH
Date: 2026-05-28
Severity: HIGH
Applies to:
- CREACION_SKILL_LF
- CREACION_PERFIL_LF
- CREACION_CARD_LF

## Problem
A profile creation was allowed to proceed under a partial approval scoped as GitHub-only. That should have been rejected because skill, profile and card creation have mandatory protocol paths.

## Security rule
For CREACION_SKILL_LF, CREACION_PERFIL_LF and CREACION_CARD_LF, partial execution is not a valid mode when it omits mandatory protocol steps.

If the user approves a partial scope such as only GitHub, without Supabase, without inventory, without report, without readback, without judge, or without close, the assistant must reject the request before write execution.

## Required block verdict
`BLOCKED_SCOPE_BYPASS_ATTEMPT`

## Required response behavior
The assistant must state that the requested partial scope conflicts with the mandatory operation path and ask for approval of the complete CREACION_*_LF protocol.

## Mandatory complete path elements
- Router
- operational source
- repo inventory
- destination validation
- creator asset
- duplicate check
- classification
- canonical design
- operational evidence pack check
- completeness
- compatibility
- rubric
- sandbox
- manifest
- rule trace
- partial scope guard
- GitHub write
- GitHub readback
- evidence log
- contract judge
- close
- report output

## Gate placement
A new `partial_scope_guard` must run before `github_write`. Contract judge, close and report output must also confirm that no partial-scope bypass was accepted.

## Fail conditions
Fail with `BLOCKED_SCOPE_BYPASS_ATTEMPT` if any of these are true:
- the approval excludes Supabase when inventory/evidence log is required;
- the approval excludes report output;
- the approval excludes readback;
- the approval asks to create only files while omitting the operation protocol;
- the approval limits execution in a way that contradicts the mandatory operation path;
- the assistant cannot prove the full path is allowed.

## ACT-0051 note
ACT-0051 must remain in SECURITY_HOLD until this security patch is read back and the relevant operation protocols include the guard.