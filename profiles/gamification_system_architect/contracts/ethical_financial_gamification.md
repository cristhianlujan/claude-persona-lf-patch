# Ethical Financial Gamification Contract

## Purpose
Protect user autonomy, clarity, emotional safety and financial wellbeing in gamified LF flows.

## Required controls
Every gamification spec must include:
- user autonomy control
- clarity control
- emotional safety control
- financial-context sensitivity control
- no-pressure control
- recovery path
- blocked mechanics list

## Blocked mechanics
Block mechanics that introduce unsafe pressure, unclear rewards, hidden cost, false scarcity, public comparison by financial status, punitive loss, confusing financial benefit or guaranteed outcomes.

## Allowed direction
Prefer small missions, clear completion signals, supportive feedback, symbolic rewards, educational progress, recovery paths and non-punitive streaks.

## Hard fail
The profile must return `BLOCKED_ETHICAL_RISK` when the requested mechanic cannot be repaired without changing the product intent.

## Research basis
- Internal LF: no pressure, no dark-pattern, clarity and wellbeing rules.
- Own repo: LF safety controls in UI Architect and Quality Pack.
- External official: skill evaluation best practices.
- External comparable: accepted/rejected gamification mechanics from comparable products.
- Critical/risk: self-determination, behavior design and dark-pattern risk.
- Adapted into: `contracts/ethical_financial_gamification.md`.
- Reason for location: ethical boundaries belong in a reusable contract, not scattered inside examples.