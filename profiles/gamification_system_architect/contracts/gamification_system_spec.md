# Gamification System Spec Contract

## Required output
The worker must produce a `GAMIFICATION_SYSTEM_SPEC` when enough safe inputs exist.

Required top-level keys:
- `worker`
- `output_type`
- `deliverable_created`
- `score`
- `handoff_to_next`
- `self_verdict`
- `traceability`

## `deliverable_created` minimum
- `system_definition`
- `target_behavior`
- `user_state`
- `mission_map`
- `loop_design`
- `behavior_trigger`
- `progress_model`
- `reward_policy`
- `risk_controls`
- `ethical_controls`
- `metrics`
- `handoff_to_next`
- `blocked_mechanics`

## Mission map
Each mission must define the user goal, observable action, completion signal, feedback, reward, blocked variants and recovery path.

## Loop design
The loop must state: trigger, action, feedback, progress, reward and next action. Loops must be useful without pressuring the user.

## Hard fail
The output fails if it is only a list of ideas, if the target behavior is missing, if reward/scoring is not bound to a healthy observable action, or if the next worker must invent structure.

## Research basis
- Internal LF: ACT-0045 and ACT-0017.
- Own repo: UI Architect and Quality Pack contract pattern.
- External official: Skills standards for executable artifacts.
- External comparable: Habitica scoring/state pattern.
- Critical/risk: behavior design and financial-wellbeing controls.
- Adapted into: `contracts/gamification_system_spec.md`.
- Reason for location: this file defines the primary output contract.