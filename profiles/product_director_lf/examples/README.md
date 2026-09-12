# Product Director LF Examples

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Patch: PATCH_PRODUCT_DIRECTOR_EXAMPLES_AND_FIXTURES_v0.1

## Purpose
This folder contains generic reusable fixtures for Product Director LF. These examples validate behavior expected by `evals/evals.json`, the mini judge and the score rubric.

## Rule
Generic profile examples live here. Project-specific cases, such as Marketplace Home, Ruta de Claridad or Simulador, must not be stored as generic examples. Specific cases belong under:

`sandbox_runs/product_director_lf/<case_id>/`

## Fixtures

| Fixture | Eval | Behavior validated | Expected verdict |
|---|---|---|---|
| `good_scope_decision.json` | `EVAL_001_GOOD_SCOPE_DECISION` | Produces a concrete Product Direction Spec with included/excluded scope, acceptance criteria and handoff. | `PASS_TO_QUALITY_PACK` |
| `missing_target_user.json` | `EVAL_002_MISSING_TARGET_USER` | Does not invent user state when target user/user state is missing. | `PRODUCT_MISSING_INPUT_STATE` |
| `blocked_uncontrolled_scope.json` | `EVAL_003_BLOCK_UNCONTROLLED_SCOPE` | Blocks uncontrolled product expansion and forces smaller safe scope. | `BLOCK_PIPELINE` |
| `self_repair_vague_acceptance.json` | `EVAL_004_REPAIR_VAGUE_ACCEPTANCE` | Detects vague acceptance criteria and returns self-repair. | `RETURN_TO_WORKER_FOR_SELF_REPAIR` |
| `good_mvp_vs_future.json` | `EVAL_005_GOOD_MVP_VS_FUTURE` | Separates MVP from future scope with clear priority rationale. | `PASS_TO_QUALITY_PACK` |
| `blocked_unsafe_financial_promise.json` | `EVAL_006_BLOCK_UNSAFE_FINANCIAL_PROMISE` | Blocks guaranteed financial promises, false urgency and hidden pressure. | `BLOCK_PIPELINE` |

## Minimum acceptance
The pack is incomplete if an eval exists without a fixture, or if a fixture does not state expected output, forbidden output and judge expectations.
