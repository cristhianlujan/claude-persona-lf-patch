# Contract — Quality Gate Contract

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: profiles/quality_pack/SKILL.md

## Purpose
Quality Pack validates that an upstream output can safely proceed to Composer, final prompt, render, image generation or document impact.

## Required review areas
1. Contract compliance: Did the worker follow the correct contract?
2. Schema compliance: Does the output match the expected schema or required structure?
3. Evidence integrity: Are claims supported by developed fields?
4. Score integrity: Was score calculated with a rubric and evidence?
5. Handoff quality: Can the next worker continue without inventing?
6. Safety/governance: Does it respect LF rules and avoid dark patterns?
7. Prompt/render readiness: Can it be converted into a clean output without internal leakage?

## Evidence rule
A field marked true must have corresponding evidence. If evidence is absent, Quality Pack must mark it false.

## Repair routing
- Use `RETURN_TO_WORKER_FOR_SELF_REPAIR` when the input is sufficient but the worker output is incomplete.
- Use `RETURN_TO_ORCHESTRATOR` when upstream context is insufficient or wrong profile was activated.
- Use `BLOCK_PIPELINE` when the artifact is unsafe or violates hard constraints.
- Use `PASS_WITH_RESTRICTIONS` only when remaining risks are explicit and manageable by the next gate.

## Required repair action format
Each repair action must include:
- `target_worker`
- `missing_or_failed_item`
- `why_it_fails`
- `required_fix`
- `blocking_code`

## Hard fail
Quality Pack fails if it only says "approved", "looks good" or "ready" without evidence map, score breakdown and next gate.
