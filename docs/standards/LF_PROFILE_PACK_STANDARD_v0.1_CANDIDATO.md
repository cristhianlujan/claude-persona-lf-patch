# LF Profile & Skill Pack Standard v0.1 CANDIDATO

Status: HISTORICAL_CANDIDATE / SUPERSEDED_FOR_TECHNICAL_MINIMUM  
Patch ID: PATCH_LF_SKILL_PROFILE_PACK_STANDARD_001  
Original source of authority: ACT-0045 — SKILL_CREADORA_PERFILES_Y_CARDS_LF_v0.1_CANDIDATO  
Created at: 2026-05-23T05:13:22.144126+00:00

## Current authority note

This May 2026 candidate introduced the pack concept and remains useful as historical/reference material, but its exact-tree minimum is no longer the canonical technical definition of Profile completeness.

Current execution must resolve live authority through Router / `public.v_lf_fuente_operativa`. The reusable technical minimum is defined by `skills/profile_creator/contracts/main_contract.md` and its deterministic depth gate. `profiles/_template` is a reference superset.

Do not copy the original 22/23-file shape into every Profile merely to satisfy this historical candidate.

## Purpose retained

Prevent LF skills and profiles from producing basic, incomplete, non-testable outputs by requiring reusable packs to be auditable, testable and evidence-bearing.

## Canonical minimum now: capabilities + evidence

A mature governed Profile must prove the applicable capabilities defined by Profile Creator, including:

- developed role, source authority, trajectory, failure behavior and authority limits;
- operational contract and failure routing;
- typed output schema;
- judge/rubric with explicit pass/fail conditions;
- traceable evidence map with exact source references;
- positive and negative evals with observable assertions;
- actionable handoff to the next independent gate;
- governance boundaries;
- user/internal output separation when user-facing output makes it applicable.

Additional folders such as checklists, examples, fixtures, local adapters and manifest remain valuable when required by the destination or when they add executable review value. They are not evidence by themselves.

## Reference superset only

The original reference shape remains available under `profiles/_template`:

```text
SKILL.md
README.md
contracts/
schemas/
judges/
checklists/
examples/
fixtures/
validators/
evals/
handoffs/
adapters/
```

The `_template` validator validates that reusable reference template. Real Profiles are validated through their own `profiles/<slug>/validators/validate_pack.py` discovered by Profile Creator.

## Non-negotiable rule retained

A skill/profile is not considered ready merely because it contains instructions or nominal files. It must expose sufficient executable contracts, schemas, quality gates, evals and evidence for independent review. File-count PASS is not semantic PASS, runtime PASS or family E2E PASS.

## Required lifecycle

```text
CANDIDATE
→ EN_REVISION
→ PRUEBA_SANDBOX
→ APROBADO
→ IMPACTO_CONTROLADO
→ VERIFICADO
→ CERRADO
```

Lifecycle labels never override live operational authority or evidence rung.

## Mandatory gates

- No official impact without Router.
- Supabase / `v_lf_fuente_operativa` is the operational source.
- Resolve the live ACT-0045 state instead of trusting this historical filename/status.
- GitHub stores technical packs.
- Human documentation does not replace runtime evidence.
- Shared policies and adapters are referenced from their canonical authority instead of copied into every Profile.
- Runtime-family success follows the `Full family E2E success contract` in Profile Creator.

## Historical sandbox note

The original candidate used a fixed full-pack validator to prove the reference scaffold itself. That test remains useful for `profiles/_template`, but it must not be used to force empty/non-applicable folders or duplicate central adapters into real Profiles.
