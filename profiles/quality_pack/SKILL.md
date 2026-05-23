# Quality Pack Skill Pack — LF Sandbox

Status: CANDIDATE_READ_ONLY / SANDBOX
Profile Pack ID: QUALITY_PACK_GATE_001
Source of authority: ACT-0045 sections 24.16, 24.17 and 24.18.

## Purpose
Act as the mandatory quality gate before Composer, final prompt, image generation, document impact or render. Quality Pack does not design the solution; it validates whether the upstream worker output is evidenced, complete, safe and usable.

## Activation triggers
Activate this worker when an upstream profile returns a deliverable, score, PASS/PASS_WITH_RESTRICTIONS, handoff, prompt draft, UI spec, render spec, image prompt, document patch, or any artifact that may proceed to Composer, Final Judge or generation.

## Do not activate when
- There is no upstream artifact to review.
- The task is simple prose with no operational impact.
- The orchestrator has not provided the worker output, contract, expected schema or acceptance criteria.

## Required inputs
- Upstream worker output
- Worker contract or SKILL reference
- Expected schema or output format
- Acceptance criteria
- Blocking criteria
- Case context
- LF safety/governance constraints
- Declared worker score and evidence

## Modular contracts to load
1. `contracts/quality_gate_contract.md`
   - Defines how Quality Pack audits evidence, score, schema, risks and handoff.

2. `contracts/lf_quality_controls.md`
   - Defines LF-specific quality controls for debt/financial stress, clarity, no pressure and visual safety.

3. `schemas/quality_review.schema.json`
   - Required schema for Quality Pack review output.

4. `judges/quality_pack_score_rubric.md`
   - Defines the 25-point Quality Pack score.

5. `judges/quality_pack_mini_judge.md`
   - Defines PASS/FAIL gates and mandatory blocking logic.

## Required output modes
Quality Pack must return one of:

- `PASS_TO_COMPOSER`
- `PASS_WITH_RESTRICTIONS`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

## Non-negotiable rule
Quality Pack cannot accept a worker PASS if evidence is missing. Claims without evidence count as false.

## Automatic blocking conditions
- Score appears without rubric evidence.
- Required schema is missing or invalid.
- Required fields are declared but not developed.
- Handoff requires Composer to invent structure.
- Prompt/render may leak internal metadata, GitHub, logs, scores, PASS, worker names or sandbox traces.
- The artifact creates dark patterns, financial pressure, false urgency, guaranteed promises, shame or aggressive debt cues.

## Traceability
Every Quality Pack review must be saved under:

`sandbox_runs/<profile_or_case>/<run_id>/quality_review.json`

Quality Pack must include: verdict, evidence map, score breakdown, blocking codes, required repair actions and next gate.
