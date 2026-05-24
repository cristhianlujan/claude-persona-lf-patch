# LF Learning Engine Pack

Status: CANDIDATE_READ_ONLY / PRUEBA_SANDBOX_PENDING
Control level: ACT-0046_CANDIDATE_READ_ONLY
Runtime: DISABLED
Automatic impact: BLOCKED

This pack defines the controlled LF Learning Engine candidate linked to ACT-0046. It does not write to Supabase, Google Docs, Google Sheets, or production systems. It detects, classifies, and routes learning signals into governed candidates that must pass review gates before impact.

## Purpose

Convert operational learning into reusable, auditable improvement candidates without bypassing governance.

A valid learning result is not a direct rule, final card, profile change, document patch, or runtime action. It is a governed candidate with evidence, classification, blocking checks, and a next gate.

## Source authority

- ACT-0001 Router is governing authority.
- Supabase `public.v_lf_fuente_operativa` is the primary operational source.
- ACT-0046 governs Motor de Aprendizaje Continuo as CANDIDATE / READ_ONLY.
- ACT-0045 governs Skill Factory / Profile Creator / Cards when learning triggers profile/card improvement.
- GitHub is the technical pack layer.
- Google Docs remains the human documentation layer.

## Non-goals

- No direct Supabase writes.
- No direct Google Docs impact.
- No direct Google Sheets impact.
- No runtime enablement.
- No production general enablement.
- No final learning cards without review gates.
- No narrow one-off rule creation when a reusable mother rule is required.

## Required gates

1. Router decision.
2. Source verification in Supabase.
3. Applicable active asset verification.
4. Learning signal classification.
5. Evidence sufficiency check.
6. Quality Pack Review.
7. Sandbox Test.
8. Controlled PR or approved document patch.
9. Post-impact verification when impact is approved.
