# Source to Decision Matrix

| Source family | Pattern extracted | LF adaptation | Destination | Limit |
|---|---|---|---|---|
| ACT-0045 | Profile pack structure and governance | Router-first, controlled impact, no runtime by default | all files | do not bypass approval gates |
| ACT-0017 | Product context for financial gamification | missions support clarity and learning | contracts and examples | no financial advice |
| Own repo UI Architect | SKILL, contracts, schemas, judges | same pack architecture | SKILL.md, contracts, schemas, judges | no UI-specific leakage |
| Own repo Quality Pack | evidence, score and handoff controls | quality gate compatibility | judges and evals | no PASS without evidence |
| Habitica | scoring/state/reward pattern | keep structure, reject harmful transfer | reward contract and references | no punitive game transfer |
| Skill standards | progressive disclosure and evals | support files only where needed | SKILL.md and evals | no empty folders |
| Behavioral models | motivation/capacity/prompt | behavior trigger contract | behavior contract | no theory-only citation |
| LF risk controls | clarity, wellbeing, no pressure | ethical gate and examples | judges/examples | no unsafe mechanic |

## Research basis
- Internal LF: ACT-0045 and ACT-0017.
- Own repo: UI Architect and Quality Pack.
- External official: skill standards.
- External comparable: Habitica and quest-style flows.
- Critical/risk: behavior and LF control models.
- Adapted into: `references/source_to_decision_matrix.md`.
- Reason for location: this file records source-to-file-to-decision traceability.