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

## Validation semantics

- The repository validator for this pack is `STRUCTURAL_ONLY`.
- A successful structural validator run is `STRUCTURAL_PASS`; it proves pack completeness and consistency only.
- It must also state `BEHAVIORAL_EVAL_NOT_EXECUTED` until cases are actually run through the Learning Engine.
- Behavioral evals are classified as `REGRESSION_EVAL` or `CAPABILITY_EVAL`.
- `BEHAVIORAL_EVAL_PASS` is reserved for isolated execution with actual-vs-expected evidence from the real execution target.

## Handoff outcome evaluation

A producer handoff must ultimately be evaluated by what the real receiver can do with it, not by whether the producer output merely satisfies a schema.

`evals/handoff_outcome_matrix.json` records producer→receiver cases while separating two different properties:

1. **Artifact consumability** — the delivered artifact is observable, resolvable and sufficiently complete for a rubric review without reconstructing missing content.
2. **Receiver execution** — a verified executable receiver target actually runs the next gate and produces captured output, trace and relevant next state.

A same-session role-play, assisted rubric review, static receiver-output fixture, or structural validator can support the first property but cannot prove the second. When no executable receiver target exists, the correct behavioral status is `BLOCKED_NO_EXECUTABLE_RECEIVER` with `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER`.

The earlier Learning Engine → Quality Pack single-case review has therefore been reclassified as `ARTIFACT_CONSUMABILITY_DEMONSTRATED_BEHAVIORAL_NOT_PROVEN`; it is not a behavioral handoff PASS. The historical Profile Creator → Quality Pack gap `CREATED_ARTIFACT_NOT_DELIVERED` is preserved, and PR #225 demonstrates its producer-side remediation, but the A→B behavioral outcome remains unproven for the same missing executable Quality Pack receiver.

No capability eval may graduate to regression protection while its behavioral outcome is blocked or unproven.

## Trace-to-change rule

A trace, failed execution, error or recurring anomaly cannot justify a patch candidate by itself. It must first be converted into a reproducible target eval. If no target eval exists, the next action is blocked with `TARGET_EVAL_REQUIRED`.

A second gate now protects handoff evals: if the required real receiver cannot be executed through a verified target, the engine must return to orchestration with `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER` instead of treating an assisted review as execution.

## Non-goals

- No direct Supabase writes.
- No direct Google Docs impact.
- No direct Google Sheets impact.
- No runtime enablement.
- No production general enablement.
- No final learning cards without review gates.
- No narrow one-off rule creation when a reusable mother rule is required.
- No claim of behavioral PASS from structural validation alone.
- No behavioral handoff PASS from same-session role-play, assisted review, static receiver fixture or structural parser.

## Required gates

1. Router decision.
2. Source verification in Supabase.
3. Applicable active asset verification.
4. Learning signal classification.
5. Evidence sufficiency check.
6. Target eval creation when a trace/error is used to justify change.
7. Eval classification: `REGRESSION_EVAL` or `CAPABILITY_EVAL`.
8. Verify that any behavioral handoff receiver has a real executable target.
9. Quality Pack Review or other applicable receiver gate.
10. Isolated Sandbox Test.
11. Behavioral eval execution and actual-vs-expected verification.
12. Controlled PR or approved document patch.
13. Post-impact verification when impact is approved.
