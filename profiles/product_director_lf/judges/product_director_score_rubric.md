# Product Director LF Score Rubric

Total: 25 points. Minimum PASS: 22/25 and no blocking product-risk condition.

## 1. Product decision clarity — 5
- 5: Clear selected decision with rationale, rejected alternatives and context.
- 3: Decision exists but rationale or rejected alternatives are incomplete.
- 1: Decision is vague or mostly directional.
- 0: No decision.

## 2. Scope control and MVP separation — 5
- 5: Included scope, excluded scope, MVP and future scope are explicit.
- 3: Scope exists but exclusions or future scope are weak.
- 1: Scope is broad or ambiguous.
- 0: No scope control.

## 3. Acceptance criteria quality — 5
- 5: Criteria are testable, concrete and aligned to the decision.
- 3: Criteria are useful but incomplete.
- 1: Criteria are vague or rely on subjective language.
- 0: No acceptance criteria.

## 4. Cross-profile handoff quality — 5
- 5: Next worker can proceed without inventing product intent, accepted scope, rejected scope, success proxy or acceptance criteria.
- 3: Handoff is mostly usable but has gaps.
- 1: Handoff is generic.
- 0: No usable handoff.

## 5. Evidence, risk and governance traceability — 5
- 5: Evidence, risks, assumptions, blockers and governance state are explicit.
- 3: Traceability exists but is incomplete.
- 1: Traceability is weak.
- 0: Claims without evidence.

## Decision quality modifier
When a decision affects scope, sequencing, prioritization or handoff, a score of 5 in categories 1, 2, 3 or 4 requires evidence that `decision_quality_requirements` protects:
- decision specificity;
- scope boundaries;
- acceptance testability;
- handoff readiness;
- risk and exclusion clarity;
- removal of vague language.

## Blocking overrides
Any of these returns BLOCK_PIPELINE regardless of score:
- unsupported financial implication
- hidden pressure or false urgency
- uncontrolled scope expansion
- specialist work taken from another profile
- PASS declared without evidence
- future scope hidden inside MVP
- vague decision language not converted into observable conditions
