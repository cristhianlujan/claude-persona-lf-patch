# Quality Pack Skill Pack — LF Sandbox

Status: CANDIDATE_READ_ONLY / SANDBOX
Profile Pack ID: QUALITY_PACK_GATE_001
Source of authority: ACT-0045 sections 24.16, 24.17 and 24.18.

## Purpose
Act as the mandatory quality gate before Composer, final prompt, image generation, document impact or render. Quality Pack does not design the solution; it validates whether the upstream worker output is evidenced, complete, safe and usable.

## Activation triggers
Activate this worker when an upstream profile returns a deliverable, score, PASS/PASS_WITH_RESTRICTIONS, handoff, prompt draft, UI spec, render spec, image prompt, document patch, or any artifact that may proceed to Composer, Final Judge or generation.

## Auto-load shared output gate
When Quality Pack reviews an artifact that may proceed to Composer, final user output, image prompt, render, tool payload, RCA or audit, it must load:

- `orchestrator/decision_logic.md`
- `learning_cards/LEARNING_CARD_OUTPUT_CHANNEL_GATE_ALLOWLIST_v0.1.md`

Quality Pack must verify that the upstream worker produced an executable artifact, not suggestions only.

If a trigger from the learning card is present and the output channel gate was not loaded, Quality Pack must return `BLOCK_PIPELINE` with blocking code `OUTPUT_CHANNEL_GATE_NOT_LOADED`.

## Do not activate when
- There is no upstream artifact to review.
- The task is simple prose with no operational impact.
- The orchestrator has not provided the worker output, contract, expected schema or acceptance criteria.

## Required inputs
- Upstream worker output
- Worker contract or SKILL reference
- Expected schema or output format
- Acceptance criteria
- Blocking criteria
- Case context
- LF safety/governance constraints
- Declared worker score and evidence

## Modular contracts to load
1. `contracts/quality_gate_contract.md`
   - Defines how Quality Pack audits evidence, score, schema, risks and handoff.

2. `contracts/lf_quality_controls.md`
   - Defines LF-specific quality controls for debt/financial stress, clarity, no pressure and visual safety.

3. `schemas/quality_review.schema.json`
   - Required schema for Quality Pack review output.

4. `judges/quality_pack_score_rubric.md`
   - Defines the 25-point Quality Pack score.

5. `judges/quality_pack_mini_judge.md`
   - Defines PASS/FAIL gates and mandatory blocking logic.

6. `../../orchestrator/decision_logic.md`
   - Defines recipient/output allowlists and gates that prevent suggestion-only outputs, internal leakage and contaminated image/tool payloads.

7. `contracts/handoff_intake_contract.md`
   - Defines the executable deterministic intake pre-check used before semantic Quality Pack review for producer→receiver continuity cases.

8. `contracts/independent_chat_semantic_review_contract.md`
   - Defines the no-additional-cost independent clean-context semantic review execution boundary.

9. `handoffs/independent_chat_semantic_review.md`
   - Copy/paste handoff template for a clean reviewer chat. It must not include a target verdict or prior semantic conclusion.

10. `schemas/independent_semantic_review_receipt.schema.json`
   - Receipt contract that separates independent semantic execution from automated semantic judge implementation.

## Deterministic handoff intake pre-check

For producer→Quality Pack continuity evaluation, run `validators/run_handoff_intake.py` before any semantic review claim.

This executable pre-check answers only whether the receiver has enough explicit context and an observable materialized upstream artifact to begin normal Quality Pack review without reconstructing producer state.

- `QUALITY_INTAKE_READY` means deterministic intake succeeded and the next gate is `SEMANTIC_QUALITY_REVIEW`.
- It does **not** mean `PASS_TO_COMPOSER`, `PASS_WITH_RESTRICTIONS`, a Quality Pack score, LF safety PASS, or general behavioral PASS.
- Missing receiver context returns to the orchestrator.
- A created artifact may be delivered by an exact reference plus materialized payload or as an explicit embedded `candidate_artifact`; in either mode its identity must match the producer claim.
- A producer that claims a created artifact but fails to deliver an observable materialized artifact or claimed components returns to the worker for self-repair.
- `semantic_quality_review_status` remains `NOT_EXECUTED` until the normal semantic Quality Pack review actually runs.

The preserved eval definition is `evals/handoff_intake_matrix.json`. The target eval must exist before changes to the intake runner that are intended to satisfy it.

## Independent clean-chat semantic review

When deterministic intake is ready but no executable independent semantic receiver exists, Quality Pack may use `INDEPENDENT_CHAT_CONTEXT` as the lowest-cost manual execution mode.

Required sequence:
1. Freeze the exact review bundle defined by `contracts/independent_chat_semantic_review_contract.md`.
2. Open a new reviewer chat/context that did not produce the artifact.
3. Paste `handoffs/independent_chat_semantic_review.md` populated only with the frozen bundle. Do not provide a prior semantic verdict, expected score or desired result.
4. Require one JSON receipt matching `schemas/independent_semantic_review_receipt.schema.json`.
5. Validate it deterministically with `validators/validate_independent_semantic_review.py`.
6. Store the validated receipt and semantic review under the case sandbox run.

A valid receipt allows the exact claim `SEMANTIC_REVIEW=EXECUTED_INDEPENDENT_CONTEXT` for that artifact. It does not mean `AUTOMATED_SEMANTIC_JUDGE=IMPLEMENTED` and does not authorize production, automatic impact or general behavioral promotion.

The receipt validator's target eval is `evals/independent_chat_semantic_review_matrix.json`.

## Required output modes
Quality Pack semantic review must return one of:

- `PASS_TO_COMPOSER`
- `PASS_WITH_RESTRICTIONS`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

The deterministic intake runner uses its separate `intake_status`; it is not a semantic Quality Pack verdict.

## Non-negotiable rule
Quality Pack cannot accept a worker PASS if evidence is missing. Claims without evidence count as false.

## Focused UI Decision validation
When the user asked for a concrete UI decision, definition or one selected visual treatment, Quality Pack must validate that the upstream output contains concrete selected values, not a vague concept or ingredient list.

Required minimum fields:
- `decision_subject`
- `selected_visual_type`
- `base_color_or_surface`
- `size_or_coverage`
- `density_limits`
- `depth_style`
- `visual_weight`
- `relationship_to_main_element`
- `implementation_format`
- `hard_exclusions`

If the answer only says what to use in general, lists ingredients, says “use layers/lines/gradients”, or gives rationale without values, Quality Pack must return `RETURN_TO_WORKER_FOR_SELF_REPAIR` with blocking code `FOCUSED_UI_DECISION_NOT_EXECUTABLE`.

## Automatic blocking conditions
- Score appears without rubric evidence.
- Required schema is missing or invalid.
- Required fields are declared but not developed.
- Handoff requires Composer to invent structure.
- Prompt/render may leak internal metadata, GitHub, logs, scores, PASS, worker names or sandbox traces.
- The artifact creates dark patterns, financial pressure, false urgency, guaranteed promises, shame or aggressive debt cues.
- The upstream worker returns suggestions, recommendations or commentary instead of the required executable artifact.
- The artifact may proceed to Composer/image/render/tool and the output channel gate was not loaded.
- Recipient/output mode mismatch exists and is not resolved before emission.
- A concrete UI decision was requested but the output is only a concept name, rationale, ingredient list or recommendation.

## Traceability
Every semantic Quality Pack review must be saved under:

`sandbox_runs/<profile_or_case>/<run_id>/quality_review.json`

Quality Pack must include: verdict, evidence map, score breakdown, blocking codes, required repair actions and next gate.

For `INDEPENDENT_CHAT_CONTEXT`, also save the validated wrapper receipt as:

`sandbox_runs/<profile_or_case>/<run_id>/independent_semantic_review_receipt.json`

Deterministic intake evidence must preserve the exact input fixture, runner revision, output and actual-vs-expected result separately from the semantic review artifact.
