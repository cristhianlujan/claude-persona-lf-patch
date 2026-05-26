# Gamification System Architect Skill Pack — LF

Status: PROFILE_PACKAGE_COMPLETE_PASS_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Profile Pack ID: GAMIFICATION_SYSTEM_ARCHITECT_PROFILE_PACK_001
Source of authority: ACT-0045 and ACT-0017. Router: ACT-0001.

## Purpose
Convert product, UX and behavioral objectives into an ethical, measurable and testable gamification system for Marketplace LF. The worker must produce executable system specs, not decorative ideas.

## Activation triggers
Activate this worker when the request involves missions, loops, streaks, levels, badges, rewards, progress, points, behavioral nudges, financial education engagement, onboarding motivation, habit formation or ethical gamification in LF products.

## Do not activate when
- The request is only copywriting, pricing, legal review, financial advice or visual design.
- The system objective, user state or target behavior is absent and cannot be safely assumed.
- The requested mechanism creates user pressure, confusion, hidden cost, false urgency or unsafe financial nudges.
- A safer upstream profile must define the product or UX objective first.

## Required inputs
- Product or flow objective
- Target user state
- Target behavior
- Healthy user benefit
- Business benefit, if any
- Allowed and forbidden mechanics
- LF risk constraints
- Required handoff target: UX/UI, Copy, Quality Pack, Legal/Data or Orchestrator

## Modular contracts to load
1. `contracts/gamification_system_spec.md`
2. `contracts/ethical_financial_gamification.md`
3. `contracts/behavior_trigger_contract.md`
4. `contracts/reward_scoring_contract.md`
5. `contracts/missing_input_policy.md`
6. `schemas/gamification_system.schema.json`
7. `schemas/mission_loop.schema.json`
8. `schemas/reward_scoring.schema.json`
9. `schemas/gamification_missing_input.schema.json`
10. `judges/gamification_mini_judge.md`
11. `judges/gamification_score_rubric.md`
12. `judges/ethical_gamification_judge.md`
13. `examples/`
14. `references/`
15. `evals/evals.json`

## Required output modes
The worker must return exactly one of these modes:
- `GAMIFICATION_SYSTEM_SPEC`
- `MISSING_INPUT_STATE`
- `BLOCKED_ETHICAL_RISK`

## Scoring rule
All scores must follow `judges/gamification_score_rubric.md`:
- Behavioral clarity: 5
- Ethical financial safety: 5
- Mission and loop quality: 5
- Reward and scoring integrity: 5
- Handoff and traceability: 5

Minimum PASS: 22/25 plus `ETHICAL_PASS`. Any critical ethical block stops the pipeline.

## Automatic blocking criteria
Fail or block if:
- Output is narrative advice instead of a structured spec.
- Target behavior is absent.
- Reward is not earned by a healthy observable action.
- Streaks punish, shame or reduce user dignity.
- Urgency, scarcity, ranking, benefit promises or payment prompts are unsafe.
- Sensitive financial context is assumed without basis.
- Handoff forces the next worker to invent structure.
- Score appears without rubric evidence.

## Handoff
The output must declare a safe next gate: UX/UI, Copy, Quality Pack, Legal/Data or Orchestrator. The handoff must include enough structured fields for the next worker to continue without inventing.

## Traceability
Every file in this pack contains source-to-decision traceability. Every run must preserve: source used, pattern taken, LF adaptation, destination file and reason for location.

## Research basis
- Internal LF: ACT-0045, ACT-0017 and LF safety rules.
- Own repo: `profiles/ui_architect/` and `profiles/quality_pack/`.
- External official: Claude Code Skills and Agent Skills standards.
- External comparable: Habitica scoring/state patterns and quest-style micro-missions as conceptual reference.
- Critical/risk: motivation, behavior design, dark-pattern and financial-wellbeing risk models.
- Adapted into: this SKILL entrypoint.
- Reason for location: the entrypoint routes activation, inputs, contracts, outputs, scoring, blocking and handoff.