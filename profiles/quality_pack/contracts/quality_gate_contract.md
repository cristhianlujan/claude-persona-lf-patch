# Contract — Quality Gate Contract

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: profiles/quality_pack/SKILL.md

## Purpose
Quality Pack validates that an upstream output can safely proceed to Composer, final prompt, render, image generation or document impact.

## Required review areas
1. Contract compliance: Did the worker follow the correct contract?
2. Schema compliance: Does the output match the expected schema or required structure?
3. Evidence integrity: Are claims supported by developed fields?
4. Score integrity: Was score calculated with a rubric and evidence?
5. Handoff quality: Can the next worker continue without inventing?
6. Safety/governance: Does it respect LF rules and avoid dark patterns?
7. Prompt/render readiness: Can it be converted into a clean output without internal leakage?
8. Unsupported additions: Did the artifact introduce visual, textual, structural, legal, financial or operational elements not supported by the user request, upstream contract, approved source or explicit safe assumption?
9. Output-shape readiness: Does the artifact match the requested channel and mode before content quality is judged?

## Evidence rule
A field marked true must have corresponding evidence. If evidence is absent, Quality Pack must mark it false.

A decision, component, metaphor, claim, metric, scene, visual object, workflow step or output section is unsupported if it cannot be traced to one of:
- user request;
- source document or approved reference;
- upstream worker contract;
- explicit Distribution Brief;
- safe assumption declared by the worker and accepted by the orchestrator.

Unsupported additions are not minor observations when the next step is Composer, final prompt, render, image generation or document impact. They must route to repair or block.

## Output shape first
Quality Pack must validate output shape before judging content quality:
- If the expected mode is RCA, the artifact must not become a final prompt.
- If the expected mode is final prompt, the artifact must not expose worker receipts, audit trails, scores, PASS labels or post-render QA as part of the payload.
- If the expected mode is worker output, the artifact must match the worker schema.
- If the expected mode is tool payload, the artifact must contain only what the tool needs.

If output shape is wrong, use `RETURN_TO_ORCHESTRATOR` or `BLOCK_PIPELINE` before content scoring.

## Repair routing
- Use `RETURN_TO_WORKER_FOR_SELF_REPAIR` when the input is sufficient but the worker output is incomplete.
- Use `RETURN_TO_ORCHESTRATOR` when upstream context is insufficient, output mode is unresolved, wrong profile was activated or output shape is wrong.
- Use `BLOCK_PIPELINE` when the artifact is unsafe, violates hard constraints, contains unsupported additions that may contaminate the final output, or would force Composer to invent structure.
- Use `PASS_WITH_RESTRICTIONS` only when remaining risks are explicit, non-blocking and manageable by the next gate without invention.

## Required repair action format
Each repair action must include:
- `target_worker`
- `missing_or_failed_item`
- `why_it_fails`
- `required_fix`
- `blocking_code`

## Unsupported additions gate
Quality Pack must block or return for repair if any of these are present without support:
- invented visual objects, scenes, decorative metaphors or UI elements;
- unsupported financial claims, metrics, percentages, guarantees or legal statements;
- workflow steps not requested or not present in the source flow;
- internal metadata, logs, scores, worker names or sandbox traces in a final user/tool payload;
- hard blockers listed by an upstream worker but not enforced in the output.

Required verdicts:
- `PASS_NO_UNSUPPORTED_ADDITIONS`
- `RETURN_TO_WORKER_UNSUPPORTED_ADDITIONS`
- `RETURN_TO_ORCHESTRATOR_OUTPUT_MODE_UNRESOLVED`
- `BLOCK_UNSUPPORTED_ADDITION_IN_FINAL_OUTPUT`
- `BLOCK_OUTPUT_SHAPE_INVALID`

## Hard fail
Quality Pack fails if it only says "approved", "looks good" or "ready" without evidence map, score breakdown and next gate.

Quality Pack also fails if it treats a blocker as a passive observation when the artifact may proceed to Composer, final prompt, render, image generation or document impact.
