# LF Profile Creator Pack

Status: CANDIDATE
Control level: PRODUCCION_CONTROLADA_READ_ONLY
Runtime: DISABLED
Automatic impact: BLOCKED

This pack defines the controlled LF skill used to create complete profile packs. It does not create final profiles directly in production. It produces profile pack candidates that must pass Quality Pack Review, Sandbox Test, and controlled PR review before any operational use.

## Purpose

Create profile packs that are reusable, auditable, and aligned with LF governance. A valid profile pack is more than a prompt: it includes contracts, schemas, judges, checklists, examples, fixtures, validators, evals, handoffs, and adapters.

## Source authority

- ACT-0001 Router is governing authority.
- Supabase `public.v_lf_fuente_operativa` is the primary operational source.
- ACT-0045 is the governing asset for Skill Factory / Skill Creator / Profile Creator / Cards.
- GitHub is the technical repository layer.
- Google Docs remains the human documentation layer.

## Non-goals

- No direct modification of ACT-0045.
- No Supabase writes.
- No runtime enablement.
- No production general enablement.
- No final profile creation without review gates.
- No infinite rule creation; consolidate into reusable mother rules.

## Required gates

1. Router decision.
2. Source verification in Supabase.
3. Applicable active asset verification.
4. Profile Creator operation.
5. Quality Pack Review.
6. Sandbox Test.
7. Controlled PR.
8. Post-merge verification.

## S26 existing-profile baseline

For `ACTUALIZACION_PERFIL_LF`, first materialize a fresh Learning Preflight bound to the target profile and current HEAD, then run:

```bash
python3 skills/profile_creator/validators/plan_s26_profile_update.py <profile_slug> <preflight_json> <repo_root>
```

The planner is read-only. It returns `BLOCKED_LEARNING_PREFLIGHT` unless the live EKB controls are traced to matched prevention rules and executable prevention evidence and the canonical pre-write execution binding matches the current target revision. Only then can it report `NO_UPDATE_REQUIRED`, `UPDATE_REQUIRED`, or `BLOCKED_AUTHORITY_REQUIRED`.

`write_allowed=true` requires both a PASS Learning Preflight and a repairable structural delta. The baseline evaluator discovers target callables statically with AST and never imports or executes target profile code.

Post-write closure requires a fresh 13/13 baseline result on the exact candidate head plus the existing operation, evidence, readback, semantic and regression gates.


## Profile Evolution Orchestrator candidate

`ACTUALIZACION_PERFIL_LF` remains the compatibility operation code. Its next architecture is defined by `contracts/profile_evolution_orchestrator_v1.json` and implemented pre-write by `validators/plan_profile_evolution.py`.

The S26 baseline remains a 13-dimension structural floor. A legacy `NO_UPDATE_REQUIRED` result from the S26 evaluator must be interpreted as `STRUCTURALLY_COMPATIBLE`; it is not proof that the profile is specialized, adaptive, expert, or evidence-optimized.

Evolution modes are `NO_CHANGE | PATCH | SPECIALIZE | ADAPT | REARCHITECT | OPTIMIZE`. Minimal patch is mandatory only for `PATCH`. Every other change still requires a bounded evidence-justified delta.

Candidate variants are reversible and non-authoritative until benchmark, challenge/assurance and admission pass. No profile source write, runtime activation, production activation, or automatic promotion is authorized by assessment or selection alone.
