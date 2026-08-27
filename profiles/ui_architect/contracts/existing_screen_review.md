# Contract — Existing Screen Review / Remediation

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: `profiles/ui_architect/SKILL.md`

## Purpose
When UI Architect evaluates or remediates an existing screen, it must convert observations into implementation-ready decisions instead of returning a repeated diagnostic list.

## Mode
Use `PRODUCTION_UI_SPEC` with `deliverable_created.screen_definition.task_mode` set to one of:
- `EVALUATE_EXISTING`
- `REMEDIATE_EXISTING`

Do not create a separate fourth output mode.

## Mandatory remediation actions
`deliverable_created.remediation_actions` is required for existing-screen evaluation/remediation.

Each action must include:
- `issue_id`: stable identifier within the case.
- `priority`: `P0`, `P1`, `P2` or `P3`.
- `category`: `LAYOUT`, `HIERARCHY`, `INTERACTION`, `COPY` or `RISK`.
- `evidence_anchor`: exact visible component/relationship that supports the finding.
- `decision`: one selected UI decision; no option list.
- `implementation_change`: what the implementing worker changes.
- `acceptance_criteria`: observable condition that proves the change was implemented.

Optional:
- `do_not`: explicit variant to avoid.

## Executability rules
- No “could use”, “should consider”, “consider”, “maybe”, “improve hierarchy” or equivalent recommendation-only wording in `decision`.
- Repeated observations must be consolidated into one action.
- A screen-level review with more than one material issue must use at least two categories when the evidence supports distinct categories.
- `evidence_anchor` must name the visible element or spatial relationship; generic labels such as “screen” or “UI” are insufficient.
- `implementation_change` must identify removal, movement, alignment, state behavior, copy replacement, spacing, sizing or another implementable change.
- `acceptance_criteria` must be testable by visual QA without reinterpretation.

## Consistency rule
When the same screen/input reaches UI Architect through router and direct profile activation, normalized `remediation_actions` must not materially diverge unless the input context differs. Routing metadata is not a reason to change UI decisions.

## LF safety
Existing LF visual governance remains mandatory. No pressure, fake urgency, dark patterns, aggressive debt cues or guaranteed outcomes may be introduced by a remediation action.
