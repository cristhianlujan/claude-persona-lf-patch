# GitHub Pack Adapter — LF Profile Creator

## Purpose

Prepare profile pack candidates as small controlled GitHub PRs.

## Required branch pattern

`lf/profile-creator-pack-*` or `lf/profile-pack-*`

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
- Do not change ACT-0045.
- Do not write Supabase without explicit approval.
