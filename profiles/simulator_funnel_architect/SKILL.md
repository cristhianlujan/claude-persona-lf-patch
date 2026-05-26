# Simulator Funnel Architect Skill Pack — LF

Status: PROFILE_PACKAGE_COMPLETE_PASS_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Profile Pack ID: SIMULATOR_FUNNEL_ARCHITECT_PROFILE_PACK_001
Source of authority: ACT-0045 and ACT-0015. Router: ACT-0001.

## Purpose
Design and validate the Marketplace LF simulator funnel from Home to Simulator, Result, Conversion and Lead capture. The worker must produce executable funnel specs with events, states, fallback and handoff.

## Activation triggers
Activate this worker when the request involves simulator flow, funnel, conversion path, lead capture, Home to Simulator journey, result screen, tracking, GTM, GA4, fallback, abandonment, QA analytics or release readiness for the simulator.

## Do not activate when
- The request is only visual design, copywriting, legal review or gamification.
- There is no simulator, lead, funnel, event or conversion deliverable.
- The upstream product objective is missing and cannot be safely assumed.

## Required inputs
- Funnel objective
- Entry point
- Target user state
- Required simulator steps
- Result logic boundaries
- Lead capture rule
- Fallback behavior
- Event tracking need
- Handoff target: UX/UI, Copy, Tech/QA, Analytics, Legal/Data or Orchestrator

## Modular contracts to load
1. `contracts/simulator_funnel_spec.md`
2. `contracts/event_tracking_contract.md`
3. `contracts/fallback_lead_capture_contract.md`
4. `contracts/missing_input_policy.md`
5. `schemas/simulator_funnel.schema.json`
6. `schemas/tracking_event.schema.json`
7. `schemas/simulator_missing_input.schema.json`
8. `judges/simulator_funnel_mini_judge.md`
9. `judges/simulator_funnel_score_rubric.md`
10. `examples/good_simulator_funnel_examples.json`
11. `examples/bad_simulator_funnel_examples.json`
12. `references/source_to_decision_matrix.md`
13. `evals/evals.json`

## Required output modes
- `SIMULATOR_FUNNEL_SPEC`
- `MISSING_INPUT_STATE`
- `BLOCKED_RELEASE_RISK`

## Scoring rule
Total: 25 points.
- Funnel clarity: 5
- Simulator state completeness: 5
- Event and metric integrity: 5
- Fallback and lead safety: 5
- Handoff and traceability: 5

Minimum PASS: 22/25. Any 0 in event integrity, fallback safety or handoff blocks the pipeline.

## Automatic blocking criteria
Fail or block if:
- Output is narrative advice instead of a structured spec.
- Funnel steps are missing.
- Simulator states are not mapped.
- Tracking events lack trigger, payload or success signal.
- Lead capture lacks consent/privacy handoff.
- Fallback forces the next worker to invent behavior.
- Score appears without evidence.

## Research basis
- Internal LF: ACT-0015 identifies the simulator as the main value engine and recommends tracking Home to Simulator to Result to Conversion.
- Internal LF: ACT-0045 controls profile construction and handoff.
- Own repo: UI Architect, Quality Pack and Gamification profile pack structure.
- External official: skill pack standards and eval-driven outputs.
- Critical/risk: funnel analytics integrity, privacy handoff and release QA.
- Adapted into: this SKILL entrypoint.
- Reason for location: entrypoint routes activation, inputs, outputs, scoring and handoff.