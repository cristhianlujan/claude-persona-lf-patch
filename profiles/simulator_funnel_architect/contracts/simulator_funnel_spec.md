# Simulator Funnel Spec Contract

## Required output
The worker must produce `SIMULATOR_FUNNEL_SPEC` when enough safe inputs exist.

Required top-level keys:
- `worker`
- `output_type`
- `deliverable_created`
- `score`
- `handoff_to_next`
- `self_verdict`
- `traceability`

## `deliverable_created` minimum
- `funnel_definition`
- `entry_points`
- `simulator_steps`
- `result_states`
- `conversion_paths`
- `lead_capture`
- `fallback_behavior`
- `tracking_plan`
- `privacy_consent_handoff`
- `qa_acceptance_criteria`
- `blocked_release_risks`
- `handoff_to_next`

## Rules
The funnel must preserve the path Home to Simulator to Result to Conversion to Lead. Each step must have state, trigger, success signal and failure behavior.

## Hard fail
The output fails if it is only advice, if simulator states are missing, if tracking events are vague, if fallback is undefined, or if the next worker must invent structure.

## Research basis
- Internal LF: ACT-0015 states simulator is the main value engine and calls for full tracking.
- Internal LF: ACT-0045 governs profile pack construction.
- Own repo: profile pack structure from UI Architect, Quality Pack and Gamification.
- External official: skill outputs should be executable and evaluated.
- Critical/risk: analytics, privacy handoff, QA and release integrity.
- Adapted into: `contracts/simulator_funnel_spec.md`.
- Reason for location: this file defines the primary simulator funnel output contract.
