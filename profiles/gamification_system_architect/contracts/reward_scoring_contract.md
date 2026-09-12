# Reward Scoring Contract

## Purpose
Define rewards and scoring that reinforce healthy progress without confusion or unsafe pressure.

## Required reward fields
- `reward_id`
- `reward_type`
- `earned_by`
- `not_earned_by`
- `financial_value`
- `symbolic_value`
- `user_benefit`
- `business_benefit`
- `risk_limit`
- `abuse_case`
- `reset_or_recovery_rule`
- `blocked_reward_patterns`
- `traceability`

## Rules
Rewards must be earned through observable user-helpful actions. Symbolic rewards are preferred when financial meaning could confuse the user. Streaks must be non-punitive and include recovery.

## Blocked reward patterns
Block unclear financial value, hidden cost, guaranteed benefit framing, payment-pressure rewards and loss mechanics that reduce user dignity.

## Research basis
- Internal LF: safe reward and no-pressure rules.
- Own repo: score/rubric evidence pattern.
- External official: eval-driven skill design.
- External comparable: Habitica shows scoring/state mechanics but LF rejects punitive transfer.
- Critical/risk: financial-wellbeing and dark-pattern risk.
- Adapted into: `contracts/reward_scoring_contract.md`.
- Reason for location: scoring and rewards need explicit rules before schemas and judges can validate them.