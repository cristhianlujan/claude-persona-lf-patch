# Behavior Trigger Contract

## Purpose
Define the behavioral mechanism behind each mission or loop.

## Required fields
- `target_behavior`
- `motivation`
- `capacity`
- `prompt`
- `prompt_timing`
- `friction_removed`
- `completion_signal`
- `feedback`
- `next_action`

## Rules
The target behavior must be observable and useful to the user. The prompt must be timely and respectful. The completion signal must be verifiable. Feedback must support progress without pressure.

## Missing or unsafe inputs
If motivation, capacity or financial context is unknown, return a missing-input state or use only low-risk assumptions that do not affect financial outcomes.

## Hard fail
Fail if the prompt relies on urgency, fear, confusion, user embarrassment or unverifiable claims.

## Research basis
- Internal LF: clarity and user-safety requirements.
- Own repo: contract-driven output pattern.
- External official: skill modular contract pattern.
- External comparable: quest-style mission structure.
- Critical/risk: behavior model mapping of motivation, capacity and prompt.
- Adapted into: `contracts/behavior_trigger_contract.md`.
- Reason for location: behavior mechanics need a dedicated contract so missions remain testable.