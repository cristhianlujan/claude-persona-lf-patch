# External Repo Patterns Review

## Own repo reviewed
- `profiles/ui_architect/`: SKILL entrypoint, contracts, schemas, judges, examples and traceability pattern.
- `profiles/quality_pack/`: quality gate, evidence map, score/rubric and blocking pattern.

## External comparable reviewed
- Habitica: scoring, state, rules and reward loops show that gamification needs contracts and limits.
- Quest-style contribution flows: small actionable missions are useful as conceptual pattern.

## Adopted patterns
- SKILL.md as main entrypoint.
- Supporting files only where needed.
- Contracts before schemas.
- Schemas before judges.
- Evals for realistic pass/block/input cases.
- Handoff must avoid invention.

## Rejected or limited patterns
- Decorative points without behavior.
- Punitive transfer from game systems into LF context.
- Public financial comparison.
- Rewards with unclear meaning.

## Research basis
- Internal LF: ACT-0045 and ACT-0017.
- Own repo: UI Architect and Quality Pack.
- External official: skill pack standards.
- External comparable: Habitica and quest-style flows.
- Critical/risk: LF control risks.
- Adapted into: `references/external_repo_patterns_review.md`.
- Reason for location: this file records what was borrowed, adapted or rejected.