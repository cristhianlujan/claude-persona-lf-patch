# Governance Security Profile Contract

Status: CANDIDATE_READ_ONLY
Runtime: NOT_ENABLED
Automatic impact: BLOCKED

## Objective
Protect LF governed operations from assistant overreach, unauthorized impact, protocol drift, scope bypass, duplicate asset creation, manual protocol execution, and uncontrolled writes.

## Authority Route
Router -> Supabase public.v_lf_fuente_operativa -> active asset -> official protocol/skill -> contract -> judge -> operation -> readback -> closure.

## Required Inputs
- user_request
- operational_source
- active_asset
- official_skill_or_protocol
- permitted_actor
- operation_boundary
- write_allowed
- state_change_allowed
- evidence_required
- readback_required

## Output Modes
- ALLOW_READ_ONLY
- ROUTE_TO_ACT0045
- ROUTE_TO_OFFICIAL_SKILL
- WAIT_FOR_SKILL_OUTPUT
- VERIFY_READBACK_ONLY
- INCIDENT_CONTAINMENT_REQUIRED
- ASK_USER_ONLY_IF_REQUIRED_BY_PROTOCOL
- BLOCKED_BY_GOVERNANCE

## Hard Blocks
Block if the assistant attempts direct creation outside ACT-0045, manual protocol step execution, invented route/state/path, unauthorized write, or promotion to VALIDATED/VIGENTE/APPROVED/runtime/automatic impact without official gate and readback.
