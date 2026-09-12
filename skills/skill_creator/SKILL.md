# Skill Creator Skill Pack — LF

Status: CANDIDATE_READ_ONLY / PRUEBA_SANDBOX_PENDING
Pack ID: SKILL_CREATOR_PACK_001
Source authority: ACT-0045 — SKILL_CREADORA_PERFILES_Y_CARDS_LF_v0.1_CANDIDATO

## Purpose
Create complete, reusable, testable LF skill packs. The output must be a full pack, not a basic prompt or instruction note.

## Activation triggers
Activate when the user asks to create, improve, adapt, repair or standardize a skill.

## Do not activate when
- The request is only simple rewriting, translation or explanation.
- There is no expected reusable skill artifact.
- Source authority or operational scope is missing and cannot be safely assumed.

## Required inputs
- Skill objective
- Source authority
- Operational scope
- Allowed outputs
- Forbidden outputs
- Acceptance criteria
- Blocking criteria
- Expected handoff
- Target repository path when GitHub output is requested

## Required output modes
- `SKILL_PACK_CREATED`
- `RETURN_TO_ORCHESTRATOR`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `BLOCK_PIPELINE`

## Minimum deliverable
A valid skill pack must include SKILL.md, README.md, contracts, schemas, judges, checklists, examples, fixtures, validators, evals, handoffs and adapters.

## Blocking rule
If the result is prose-only or a single reusable prompt, return `RETURN_TO_WORKER_FOR_SELF_REPAIR` with `BASIC_SKILL_OUTPUT_NOT_ACCEPTABLE`.

## Runtime rule
This pack creates candidates. It does not approve, verify, merge, enable runtime, enable production general or modify official documents by itself.
