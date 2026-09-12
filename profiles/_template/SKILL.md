# LF Profile Pack Template — SKILL.md

Status: GENERIC_REUSABLE_TEMPLATE / SANDBOX_PASS

## Purpose

Define a reusable LF profile pack that can produce structured, validated outputs instead of generic prose.

## Activation triggers

Activate when a profile must produce a reusable operational output, review artifact, UI spec, documentation patch, handoff or quality-gated deliverable.

## Required inputs

- Objective
- Scope
- Allowed outputs
- Forbidden outputs
- Source authority
- Acceptance criteria
- Blocking criteria
- Expected handoff

## Required output modes

- `VALID_OUTPUT`
- `RETURN_TO_ORCHESTRATOR`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `BLOCK_PIPELINE`

## Blocking rule

A basic prompt or prose-only answer is invalid and must return `RETURN_TO_WORKER_FOR_SELF_REPAIR` with blocking code `BASIC_SKILL_OUTPUT_NOT_ACCEPTABLE`.

## Required modules

Load contracts, schemas, judges, checklists, examples, fixtures, validators, evals, handoffs and adapters before declaring the profile ready.
