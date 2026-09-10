# MOTOR — SKILL execution route candidate

This bundle records the autonomous sandbox candidate discovered while rerunning the real AUD-018 case end to end.

## Scope

- Candidate operation: `EJECUCION_SKILL_LF`.
- Target behavior: generic, governed, read-only execution of an existing `SKILL`.
- Trigger case: EKB `AUD-018`.
- No production enablement, runtime promotion, automatic impact, official document edit, S26 change, or S30 change.
- The persistent Router remains unchanged after each sandbox window; `SKILL/EXECUTE` is removed before commit and the operation stack returns to `CANDIDATO_READ_ONLY`.

## Real route

Before candidate activation, the exact request `ACT-0046 / SKILL / EXECUTE / DIRECT` returned `BLOCKED / BLOCK_OPERATION_NOT_REGISTERED`.

Inside the controlled sandbox window it returned `READY_TO_EXECUTE / EJECUCION_SKILL_LF`, with 1 contract, 9 steps and 4/4 required policies resolved.

The full ACT-0046 execution then produced a bounded `PATCH_CANDIDATE_READY` result. The run did **not** self-certify semantic PASS: step 70 and final reporting returned to Router because independent semantic evidence is still pending.

## Regression

A 23-case before/after Router matrix covered SKILL, PERFIL, ADAPTER, DOC, REGLA, CARD, STRATEGY, DB, FUNCTION, MIGRATION, TRIGGER, KNOWLEDGE and OPERATION_CODE surfaces. Exactly two target cases changed (`SKILL/EXECUTE` existing and missing target); 21 non-target cases were byte-equivalent as JSONB before and during the activation window.

Existing unrelated blockers were preserved rather than hidden, including Quality Pack execution blocked by its current runtime state and Strategy creation blocked by missing active contract. They were identical before/after and therefore were not introduced by this candidate.

## Open gates

1. `ACT0046_SOURCE_PARITY_DRIFT`: the official Google Doc and `skills/learning_engine/SKILL.md` currently use different output/runtime semantics.
2. `INDEPENDENT_SEMANTIC_REVIEW_PENDING`: AUD-018 forbids a same-context execution from declaring its own independent semantic PASS.
3. Promotion/activation remains out of scope; this PR is evidence + candidate specification only.

## Merge isolation

This branch was created directly from `main@5f33c4ce25fca201c109d31be5c2e1e1ec465afc`. It does not depend on PR #640 and shares no path with its `skills/learning_engine/evals/real_cases/aud018_route_baseline/**` scope.