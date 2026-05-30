# Judge — Security Governance Mini-Judge

Status: CANDIDATE_READ_ONLY / SECURITY_HOLD_REPAIR
Applies to: `perfiles/seguridad_gobernanza_lf/SKILL.md`
Execution repair id: `EXEC-PERFIL-SEGURIDAD-GOBERNANZA-LF-20260530-001`

## Purpose

Validate that the Security Governance profile produced an executable governance decision, not advice, not a loose checklist and not a closure by confidence.

## Required checks

1. Output is a structured Security Governance Decision Pack.
2. Router ACT-0001 and Supabase operational source were checked or a blocking reason is present.
3. Asset state and control level are explicitly reported.
4. Operation protocol is selected or explicitly blocked.
5. Scope binding separates allowed, prohibited and out-of-scope work.
6. Authorization binding is exact for every write or state change.
7. Required evidence is mapped to steps.
8. Step enforcement exists for every required step.
9. Tool permissions are constrained by exact destination.
10. Readback plan exists before impact.
11. Judge plan exists before closure.
12. Decision uses allowed decision values.
13. Blocking codes are explicit when blocked.
14. Next gate is actionable and safe.
15. Trace path includes execution_id when closure or state change is involved.

## Automatic PASS conditions

PASS only if:

- no hard-fail condition exists;
- all required fields are present;
- all claimed evidence is mapped to a source;
- all writes/state changes have authorization and readback;
- closure is not claimed unless closure gate passed.

## Automatic FAIL / BLOCKED conditions

Return BLOCKED if any condition is true:

- `router_missing`
- `operational_source_missing`
- `active_asset_unverified`
- `operation_protocol_missing`
- `scope_binding_missing`
- `authorization_ambiguous`
- `write_destination_unvalidated`
- `execution_id_missing_for_closure`
- `required_steps_missing_for_closure`
- `research_pack_missing_for_creation_or_repair`
- `weak_research_pack_evidence`
- `step_enforcement_missing`
- `readback_missing_after_write`
- `judge_missing_for_closure`
- `log_used_as_execution_substitute`
- `runtime_enabled`
- `automatic_impact_enabled`
- `security_hold_lifted_without_gate`
- `approved_or_verified_claim_without_gate`
- `double_truth_unresolved`
- `support_pack_missing`

## Blocking codes

Use these codes exactly when applicable:

- `BLOCKED_EXECUTION_ID_REQUIRED`
- `BLOCKED_REQUIRED_STEPS_MISSING`
- `BLOCKED_RESEARCH_PACK_NOT_EXECUTED`
- `BLOCKED_RESEARCH_PACK_EVIDENCE_WEAK`
- `BLOCKED_JUDGE_REQUIRED_STEP_MISSING`
- `BLOCKED_CLOSE_WITHOUT_OPERATION_EXECUTION`
- `BLOCKED_STEP_ENFORCEMENT_PACK_MISSING`
- `BLOCKED_APPROVAL_AMBIGUOUS`
- `BLOCKED_DESTINATION_NOT_VALIDATED`
- `BLOCKED_READBACK_REQUIRED`
- `BLOCKED_DOUBLE_TRUTH_UNRESOLVED`
- `SECURITY_HOLD_OPERATIVO`

## Verdicts

- `PASS`: complete, safe and executable, with no closure bypass.
- `PASS_WITH_RESTRICTIONS`: usable for review package only; no approval or closure.
- `NEEDS_INPUT`: orchestrator must supply missing scope, destination or authorization.
- `NEEDS_ADJUSTMENT`: profile must self-repair using existing input.
- `BLOCKED`: unsafe, incomplete or closure/impact attempted without gate.

## Output

Mini-judge must return:

- `verdict`
- `evidence_by_check`
- `missing_outputs`
- `blocking_codes`
- `allowed_next_gate`
- `blocked_next_gate`
- `trace_path`

## Hard fail

The mini-judge fails if it validates a paragraph, validates a checklist without step evidence, accepts log-only closure, accepts GitHub readback as full protocol closure, or allows state uplift while the asset remains under Security Hold.
