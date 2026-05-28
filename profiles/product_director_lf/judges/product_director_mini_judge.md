# Product Director LF Mini Judge

## Purpose
Validate that Product Director LF produced an executable product decision, safe scope and usable handoff.

## Required checks
1. Output validates against the expected schema.
2. A concrete product decision exists.
3. Included scope and excluded scope are both present.
4. Acceptance criteria are testable.
5. Priority and rationale are explicit.
6. Risks and blockers are visible.
7. Handoff can be used without inventing product intent.
8. Score includes rubric evidence.
9. Traceability exists.
10. When the decision affects scope, sequencing, prioritization or handoff, `decision_quality_requirements` must protect specificity, scope boundaries, testability, handoff readiness and exclusion clarity.

## Automatic FAIL conditions
- Output is only narrative advice.
- Product decision is missing.
- Included or excluded scope is missing.
- Acceptance criteria are vague.
- Handoff requires invention by UX/UI, Copy, Tech, Legal/Data, QA or Orchestrator.
- The decision creates uncontrolled scope expansion, overpromise, hidden pressure or unsafe financial meaning.
- The worker performs specialist work reserved for another profile.
- Score appears without evidence.
- The decision uses vague terms without turning them into observable conditions.
- The output says MVP but hides future scope inside current scope.
- The next worker would need to decide product intent, accepted scope, rejected scope or acceptance criteria.

## Verdicts
- `PASS_TO_QUALITY_PACK`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

## Research basis
- Internal LF: ACT-0001, ACT-0045 and corrected CREACION_PERFIL_LF flow.
- Own repo: UI Architect, Quality Pack, Gamification Architect, Profile Creator and Learning Engine package patterns.
- Product governance: product direction must define decision, scope, acceptance and handoff.
- Risk control: human approval remains required for final impact.