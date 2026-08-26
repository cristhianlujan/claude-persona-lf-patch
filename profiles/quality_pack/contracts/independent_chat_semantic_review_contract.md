# Contract — Independent Chat Semantic Review

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: `profiles/quality_pack/SKILL.md`
Execution mode: `INDEPENDENT_CHAT_CONTEXT`

## Purpose
Provide a no-additional-cost semantic Quality Pack review path that is independent from the producer conversation and does not depend on Copilot, a paid external API, or a provider-specific judge.

This contract does not automate semantic judgment. It standardizes what a clean reviewer context receives, what it must return, and what can be claimed after deterministic receipt validation.

## Preconditions
1. Deterministic handoff intake already returned `QUALITY_INTAKE_READY` when that pre-check applies.
2. The reviewer runs in a new chat/context that did not produce the artifact under review.
3. The reviewer receives only the frozen review bundle defined below. Do not provide a previous semantic verdict, expected score, assisted review conclusion, or desired outcome.
4. The exact artifact under review is materialized in the bundle or resolvable by an exact immutable reference.
5. No paid external model/API is required for this execution mode.

## Frozen review bundle
The handoff must provide:
- `review_case_id`
- exact `artifact_ref` and, when available, immutable SHA/digest
- full artifact payload or exact resolvable materialized artifact
- upstream worker contract/SKILL reference and relevant content
- `contracts/quality_gate_contract.md`
- `contracts/lf_quality_controls.md` when applicable
- `judges/quality_pack_score_rubric.md`
- `judges/quality_pack_mini_judge.md`
- `schemas/quality_review.schema.json`
- acceptance criteria, blocking criteria, case context and LF governance constraints needed to judge the artifact

The bundle must not include a producer-authored target verdict or a previous semantic review as an instruction to the independent reviewer.

## Reviewer rules
The independent reviewer must:
1. Evaluate the artifact from the frozen bundle only.
2. Treat unsupported claims as unsupported; do not reconstruct missing producer state.
3. Apply the 25-point Quality Pack rubric exactly.
4. Apply hard LF safety/governance failures regardless of numeric score.
5. Use only one allowed semantic verdict:
   - `PASS_TO_COMPOSER`
   - `PASS_WITH_RESTRICTIONS`
   - `RETURN_TO_WORKER_FOR_SELF_REPAIR`
   - `RETURN_TO_ORCHESTRATOR`
   - `BLOCK_PIPELINE`
6. Produce an evidence map tied to observable fields/content in the supplied artifact.
7. Return the receipt JSON only; no explanatory prose outside the JSON.

## Required independence metadata
The receipt is valid for this mode only when it declares:
- `execution_mode = INDEPENDENT_CHAT_CONTEXT`
- `semantic_status = EXECUTED_INDEPENDENT_CONTEXT`
- `reviewer_is_producer = false`
- `producer_context_available = false`
- `external_paid_model_used = false`
- `automated_semantic_judge_implemented = false`
- `review_completed = true`

These fields describe the execution boundary; they are not evidence that the semantic verdict itself is correct.

## Deterministic receipt validation
Run:

`python profiles/quality_pack/validators/validate_independent_semantic_review.py <receipt.json>`

The validator checks execution metadata, required source references, score arithmetic, verdict/score compatibility, required evidence containers and output shape. It does not re-perform the semantic review.

## Claim boundary
After a receipt passes deterministic validation, LF may claim:

`SEMANTIC_REVIEW=EXECUTED_INDEPENDENT_CONTEXT`

LF must not infer from that fact alone:
- `AUTOMATED_SEMANTIC_JUDGE=IMPLEMENTED`
- general behavioral PASS
- regression promotion
- production or automatic impact authorization

The semantic verdict remains the reviewer result for the exact reviewed artifact and frozen bundle only.
