# GitHub Pack Adapter — LF Learning Engine

## Purpose

Prepare learning engine candidates as small controlled GitHub PRs.

## Required branch pattern

`lf/learning-engine-*` or `lf/learning-candidate-*`

## Required PR controls

- Draft PR first.
- CI validators must pass.
- Quality Pack Review required.
- Sandbox Test required before merge recommendation.
- Pre-merge comment required.
- Explicit user approval required for merge.

## Forbidden actions

- Do not merge automatically.
- Do not enable runtime.
- Do not change ACT-0046.
- Do not change ACT-0045.
- Do not write Supabase without explicit approval.
- Do not patch Google Docs without explicit approval.
