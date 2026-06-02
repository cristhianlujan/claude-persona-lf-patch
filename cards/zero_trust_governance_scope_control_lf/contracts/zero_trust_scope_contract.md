# Zero Trust Governance Scope Control Contract

Status: CANDIDATE_READ_ONLY
Runtime: NOT_ENABLED
Automatic impact: BLOCKED

## Objective
Ensure no instruction, memory, handoff, prior output, tool access, or assistant confidence authorizes operational impact by itself.

## Required Scope Checks
- exact_user_request
- explicit_authorization
- excluded_scope
- source_of_truth
- active_asset
- owning_skill_or_protocol
- assistant_role
- write_allowed
- state_change_allowed
- readback_required

## Output Modes
- SCOPE_CONFIRMED
- SCOPE_REDUCED
- RETURN_TO_ROUTER
- WAIT_FOR_SKILL_REQUEST
- BLOCKED_SCOPE_BYPASS
- BLOCKED_EXCESSIVE_AGENCY
- BLOCKED_UNAUTHORIZED_WRITE
- READY_FOR_READ_ONLY_DESIGN

## Hard Blocks
Block implicit authorization, memory-over-source behavior, prior invalid execution reuse, invented names/folders/states, manual protocol steps, and unauthorized production/validated/approved/vigente/runtime/automatic impact.
