# Safe AI Governance Card Contract

Status: CANDIDATE_READ_ONLY
Runtime: NOT_ENABLED
Automatic impact: BLOCKED

## Objective
Separate reasoning, recommendation, preparation, execution, approval, verification, and impact for LF governed operations.

## Required Checks
- source_of_truth
- active_project
- active_asset
- official_skill_or_protocol
- allowed_actor
- allowed_operation
- evidence_required
- user_approval_required_by_protocol
- read_only_or_write_impact

## Output Modes
- SAFE_READ_ONLY
- ROUTE_TO_SKILL
- WAIT_FOR_PROTOCOL
- BLOCKED_UNAUTHORIZED_ACTION
- NEEDS_USER_DECISION
- INCIDENT_CONTAINMENT
- VERIFY_ONLY

## Hard Blocks
Block manual protocol execution, unauthorized writes, invented process, unnecessary microapprovals, source bypass, evidence-free incident closure, and unauthorized VALIDATED/VIGENTE/APPROVED/runtime/automatic impact states.
