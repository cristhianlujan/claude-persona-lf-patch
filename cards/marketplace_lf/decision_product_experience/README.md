# Marketplace LF Decision Product Experience Card Pack

Status: RUNTIME_PACK_CANDIDATE / READ_ONLY
Control level: CONTROLADO
Runtime: DISABLED
Automatic impact: BLOCKED
Validated: false

This pack defines the executable candidate card for MarketPlace Libertad Financiera product and experience decisions. It is not a generic LF card, not a Juan Digital-only card, and not a production runtime.

## Source authority

- ACT-0001 Router / operational governance.
- Supabase `public.v_lf_fuente_operativa` as operational source.
- ACT-0045 `SKILL_CREADORA_PERFILES_Y_CARDS_LF_v0.1_CANDIDATO` as governed creator skill for profiles/cards.
- MarketPlace LF active Drive root and project research as human documentation layer.
- GitHub as executable technical pack layer.

## Purpose

Help evaluate MarketPlace LF product, UX/UI, trust, behavioral, ethical gamification, copy-sensitive and visual decisions using a repeatable contract, schema, judge and sandbox evals.

## Non-scope

- No production changes.
- No Home official edits.
- No Drive writes from this pack.
- No Supabase writes from this pack.
- No runtime enablement.
- No VALIDATED marking.
- No final product approval.
- No legal/compliance final approval.

## Required gates

1. Router-first routing.
2. Supabase source verification.
3. Active asset verification.
4. Card operation in candidate/read-only mode.
5. Quality Pack Review.
6. Sandbox Test with Juan Digital and map surface cases.
7. Controlled PR review.
8. Explicit user approval before merge or official registration.

## Files

- `README.md`
- `CARD.md`
- `context_pack.md`
- `contracts/main_contract.md`
- `contracts/missing_input_policy.md`
- `schemas/decision_request.schema.json`
- `schemas/decision_output.schema.json`
- `judges/decision_judge.md`
- `judges/score_rubric.md`
- `examples/juan_digital_case.md`
- `examples/map_surface_case.md`
- `fixtures/juan_digital_decision_request.json`
- `fixtures/map_surface_decision_request.json`
- `fixtures/missing_source_decision_request.json`
- `evals/evals.json`
- `handoffs/to_quality_pack.handoff.json`
- `adapters/github_pack_adapter.md`
- `adapters/documentation_adapter.md`
- `validators/validate_pack.py`
