# Contract — Frontend Prototype Missing Input Policy

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/frontend_prototype_architect_lf/SKILL.md`

## Purpose
Define when Frontend Prototype Architect must stop instead of inventing product, UI or technical decisions, without treating every omitted field in the latest message as missing.

## Resolution order before declaring missing input
1. Current user request and attachments.
2. Current conversation/upstream profile output already supplied to this worker.
3. Router payload or governed execution context.
4. Existing approved Product/UI contract for the same screen/version.
5. Safe implementation defaults that do not alter product intent, claims, CTA intent, visual hierarchy or runtime boundary.

Never ask again for a value already resolved by a higher-priority source. For an incremental request, preserve unchanged authoritative values from the previous version and isolate only the delta.

## Continue with governed context when
A field is absent from the latest sentence but is already authoritative and unambiguous in the available context. Examples include an unchanged viewport, route, CTA label, brand token or sandbox path.

Safe implementation defaults may be used only for low-risk frontend mechanics that do not create a product/UI decision. Every such assumption must be listed in `source_inputs` or `traceability`.

## Return `FRONTEND_MISSING_INPUT_STATE` when
After the resolution order above, at least one unresolved item would force the worker to invent or choose among materially different product/UI decisions, including:
- Product Direction authority is unavailable or conflicts materially.
- UI structure/hierarchy authority is unavailable or conflicts materially.
- CTA intent or route has contradictory authoritative values.
- Allowed/forbidden content conflict affects claims or user meaning.
- A missing target mode makes materially different implementations plausible and no safe responsive default preserves the approved UI intent.
- Sandbox destination cannot be resolved without writing outside the allowed prototype boundary.
- Accessibility requirement conflicts with an upstream requirement and cannot be repaired without changing product/UI intent.

Do not block solely because a Product/UI spec is not repeated verbatim in the latest message.

## Redirection contract
The worker never calls Product Director, UI Architect, Shell governance, a backend owner or the final user directly to resolve a material gap. It returns one typed routing intent to the orchestrator; ACT-0001/Router remains responsible for selecting and invoking the next profile, skill or adapter.

Every `FRONTEND_MISSING_INPUT_STATE` must validate against `schemas/frontend_missing_input.schema.json` and contain:
- `pipeline_action = RETURN_TO_ORCHESTRATOR`;
- exactly one `resolution_target` among `PRODUCT_DIRECTION`, `UI_ARCHITECT`, `LF_SHELL_GOVERNANCE`, `ORCHESTRATOR_DECISION`;
- one minimal `question_to_orchestrator` describing only the unresolved decision;
- `resolved_from_context` so already-known values are not requested again.

For requests that are outside the frontend sandbox boundary, use `BLOCKED_FRONTEND_SCOPE` and validate against `schemas/frontend_scope_block.schema.json`:
- `RETURN_TO_ORCHESTRATOR` when another governed capability may own the request;
- `BLOCK_PIPELINE` only when the request cannot safely proceed in the current pipeline;
- a Shell change must return `SHELL_CHANGE_REQUIRED -> RETURN_TO_ORCHESTRATOR -> LF_SHELL_GOVERNANCE`.

## Contradictory or late-changing inputs
When requirements change:
- identify `changed_now`;
- identify `preserved_from_context`;
- identify `conflicts_detected`;
- apply the newest authoritative delta when authority is clear;
- otherwise request only the one decision needed to resolve the conflict.

A stale previous answer is not evidence. The current delta must be reflected in the resulting implementation decision.

## Minimum output
- missing_fields
- resolved_from_context
- conflicts_detected
- why_required
- risk_if_assumed
- pipeline_action
- resolution_target
- question_to_orchestrator

## Rule
Request only the minimum missing information. Do not ask for data already available in Router, Supabase, GitHub sandbox runs or upstream profile outputs. Structural completeness is not a reason to discard sufficient governed context.
