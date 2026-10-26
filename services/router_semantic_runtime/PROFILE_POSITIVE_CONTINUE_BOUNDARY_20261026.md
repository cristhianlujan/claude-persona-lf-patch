# Positive profile continuation boundary — 2026-10-26

ACT-0001 remains the only routing authority between profiles.

When a governed profile output declares:
- `routing.via = ORCHESTRATOR`
- `routing.pipeline_action = CONTINUE` or `CONTINUE_WITH_RESTRICTIONS`
- a non-empty, non-`NONE` `routing.resolution_target`

the post-profile classifier must return the result to ACT-0001 Stage1 instead of treating it as terminal.

The `resolution_target` is context for reclassification. It is not direct profile invocation authority. ACT-0001 must still perform its normal deterministic candidate discovery, semantic profile selection and Gate2.

Existing `RETURN_TO_ORCHESTRATOR` behavior and genuinely terminal outputs remain unchanged.
