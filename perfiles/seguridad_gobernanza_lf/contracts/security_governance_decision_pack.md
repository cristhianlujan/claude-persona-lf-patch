# Contract — Security Governance Decision Pack

Status: CANDIDATE_READ_ONLY / SECURITY_HOLD_REPAIR
Applies to: `perfiles/seguridad_gobernanza_lf/SKILL.md`
Execution repair id: `EXEC-PERFIL-SEGURIDAD-GOBERNANZA-LF-20260530-001`

## Purpose

The Security Governance profile must produce an executable decision artifact before any LF governance operation proceeds to write, register, approve, validate or close an asset.

This contract prevents suggestion-only outputs, conversational approvals, closure by log only and direct entry into skills/cards/adapters without Router and operational source verification.

## Mandatory output object

The profile output must be a `Security Governance Decision Pack` with these required keys:

- `profile`
- `mode`
- `route_applied`
- `assets_checked`
- `operation_protocol`
- `scope_binding`
- `authorization_binding`
- `risk_register`
- `required_evidence`
- `step_enforcement`
- `tool_permissions`
- `readback_plan`
- `judge_plan`
- `decision`
- `blocking_codes`
- `next_gate`
- `trace_path`
- `self_verdict`

## Required route fields

`route_applied` must include:

- `router`: ACT-0001 or blocking reason;
- `operational_source`: Supabase view/table consulted or blocking reason;
- `active_asset`: asset code, state and control level;
- `adapter_or_protocol`: operation_code or reason not applicable;
- `verification`: readback/judge/evidence plan;
- `closure`: allowed only after formal gate.

## Scope binding

`scope_binding` must separate:

- requested work;
- allowed work;
- prohibited work;
- out-of-scope work;
- state changes allowed;
- state changes blocked.

If the user says only `ok`, `continua`, `arreglalo`, `conforme`, `subelo`, `impacta`, or similar, this is not enough to infer approval for unrelated destinations or state changes.

## Authorization binding

Every impact must define:

- exact system;
- exact repo/file/table/document;
- exact operation;
- expected state after impact;
- whether approval exists;
- whether readback is required.

If authorization is incomplete, return `BLOCKED_APPROVAL_AMBIGUOUS` or `NEEDS_SCOPE_CONFIRMATION`.

## Step enforcement

For each required protocol step, `step_enforcement` must state:

- `step_id`;
- required status;
- input evidence;
- output evidence;
- validation rule;
- blocking code;
- trace path;
- next gate.

Any required step without enforcement blocks closure with `BLOCKED_STEP_ENFORCEMENT_PACK_MISSING`.

## Closure gate

The profile may emit `CLOSURE_PASS` only when all are true:

1. `execution_id` exists in `lf_operation_execution`.
2. Required steps exist in `lf_operation_execution_steps`.
3. Required steps are PASS or allowed NOT_APPLICABLE_JUSTIFIED.
4. Critical steps have strong evidence.
5. GitHub/Drive/Supabase readback passed when impact occurred.
6. Judge PASS exists.
7. Operational log references execution_id.
8. No security hold remains unresolved.

## Hard fail

Automatic fail if:

- output is free-form prose;
- Router or operational source is missing;
- closure is attempted without execution_id;
- log is used as substitute for execution;
- runtime or automatic impact is enabled;
- approved/read-only/verified/100% status is claimed without formal gate;
- research pack is missing for profile/card/skill creation or repair;
- support pack files are missing;
- double truth is unresolved.
