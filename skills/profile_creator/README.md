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
