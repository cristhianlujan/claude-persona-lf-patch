# LEARNING_CARD_OUTPUT_MODE_COMPLETENESS_v0.1

Status: CANDIDATE_READ_ONLY / SANDBOX  
Applies to: Skill Creator, Profile Creator, Card Creator, adapters, workers, judges, Quality Pack and any LF skill with structured outputs.

## Problem observed

A profile can describe a new output mode inside `SKILL.md` but still fail at runtime if the mode does not have a complete enforcement package.

Observed failure:

- UI Architect added `Focused UI Decision Spec` as a mode.
- The mode required concrete UI values.
- There was no dedicated JSON Schema for that mode.
- The mini judge was still mostly validating `Production UI Spec` / Component Tree.
- The worker returned prose or visual ingredients instead of an executable decision.
- Quality Pack could identify the issue conceptually but did not have a strict schema assert at the first gate.

## Learning

Do not treat a new output mode as complete just because it appears in `SKILL.md`.

A structured output mode is complete only when the full enforcement package exists.

## Rule — Output Mode Completeness

When creating or modifying a profile/skill, every output mode must be complete.

A complete output mode requires:

1. explicit activation condition;
2. required output fields;
3. schema when fields must be machine-checkable;
4. mini judge validation for that output mode;
5. Quality Pack or equivalent gate validation;
6. PASS and FAIL sandbox cases;
7. blocking code for non-executable outputs.

## Blocking logic

```text
IF output_mode is described only in SKILL.md
AND output_mode requires structured fields
AND no schema or mini-judge branch exists
THEN BLOCK_WITH_CODE: OUTPUT_MODE_INCOMPLETE

IF worker returns prose, concept name, rationale, ingredient list or recommendation when a structured decision is required
THEN RETURN_TO_WORKER_FOR_SELF_REPAIR_WITH_CODE: OUTPUT_MODE_NOT_EXECUTABLE
```

## Scope

This is not a UI-only rule.

It applies to any LF profile/skill that produces:

- focused decisions;
- final prompts;
- tool payloads;
- patches;
- SQL;
- JSON;
- document drafts;
- audit/RCA reports;
- visual specs;
- cards;
- handoffs to Composer;
- any artifact that must be verifiable.

## Maintenance rule

Do not create a new rule for each product section or visual failure.

Before adding a new rule, classify the failure under:

- missing output mode schema;
- mini judge not aligned with output mode;
- Quality Pack lacks structural assert;
- Composer received prose instead of artifact;
- output mode only exists as prose inside SKILL.md;
- runtime did not load the latest profile package.

Only create a new rule if the failure cannot be classified under those categories.

## PASS criteria

PASS if a new or modified output mode includes:

- mode trigger;
- required fields;
- schema or justified no-schema decision;
- mini judge branch;
- Quality Pack/gate validation;
- PASS case;
- FAIL case;
- blocking code.

## FAIL criteria

FAIL if:

- a mode is only described in SKILL.md;
- a structured mode has no schema;
- mini judge only validates a different mode;
- Quality Pack evaluates intention but not structure;
- worker can still answer in prose;
- Composer must invent structure;
- negative test does not fail.

## Required consultation

Skill Creator / Profile Creator must consult this learning card before creating or modifying:

- any profile output mode;
- any new worker deliverable;
- any schema-dependent artifact;
- any judge or mini judge;
- any Composer handoff;
- any prompt/image/tool payload pipeline.

## Status

CANDIDATE / REQUIRES_SANDBOX
