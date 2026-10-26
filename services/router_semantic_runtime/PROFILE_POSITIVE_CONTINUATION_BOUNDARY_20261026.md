# ACT-0001 positive profile continuation boundary — 2026-10-26

Purpose: preserve governed profile chaining after a successful profile result.

Required behavior:
- A profile result with routing.pipeline_action = CONTINUE or CONTINUE_WITH_RESTRICTIONS and routing.via = ORCHESTRATOR must not terminate as COMPLETE when routing.resolution_target names a next gate/capability.
- The result returns to ACT-0001 Stage1 with route_policy = REPEAT_FULL_ROUTER_FLOW.
- The prior profile selection is advisory only and is never reused as authority.
- direct_profile_invocation_allowed remains false.
- target_profile remains forbidden.
- The exact upstream profile output is carried in the Router-return payload so the next governed profile can review the actual artifact rather than a Router-created summary.
- resolution_target is a routing hint, not direct profile authority; ACT-0001 performs deterministic candidate discovery and semantic selection again.
- A profile output with no routing continuation remains terminal and may emit normally.
- Existing RETURN_TO_ORCHESTRATOR behavior remains unchanged.

Regression motivating this boundary:
Evidence Lineage Reviewer returned PASS_WITH_RESTRICTIONS / CONTINUE_WITH_RESTRICTIONS / QUALITY_PACK, but lf_profile_result_router_return_classify_v1 previously returned COMPLETE / EMIT_PROFILE_RESULT.
