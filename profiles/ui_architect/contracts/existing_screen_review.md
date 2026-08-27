# Contract — Existing Screen Review / Remediation V4

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: `profiles/ui_architect/SKILL.md`

## Purpose
When UI Architect evaluates or remediates an existing screen, it must convert observations into implementation-ready, evidence-bound decisions instead of returning a repeated diagnostic list.

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
- `evidence_component_ids`: one or more Component Tree IDs that contain the evidence; the execution target must be among them.
- `decision`: one selected UI decision; no option list.
- `implementation_change`: human-readable implementation instruction that names the target-specific concept and the transformation.
- `acceptance_criteria`: observable, target-specific QA condition.
- `execution`:
  - `operation`: one of `REMOVE`, `MOVE`, `ALIGN`, `REPLACE_COPY`, `RESIZE`, `REORDER`, `SET_STATE`, `SET_SPACING`, `MERGE`, `SPLIT`, `HIDE`, `SHOW`, `CHANGE_TOKEN`.
  - `target_component_id`: existing Component Tree ID.
  - `property`: concrete property/state/copy being changed.
  - `desired_value`: concrete target state/value.
- `acceptance_check`:
  - `check_type`: machine/QA-observable type compatible with the operation.
  - `target_component_id`: must equal the execution target.
  - `expected`: expected observable result.

Optional:
- `do_not`: explicit variant to avoid.
- `semantic_authority`: required whenever an action changes copy/business meaning or state.
  - `source_refs`: non-empty references to raw input/upstream authority.
  - `authority_type`: e.g. `RAW_INPUT`, `UPSTREAM_PRODUCT_CONTRACT`, `CONSERVATIVE_REDUCTION`.
  - `claim_boundary`: what the source does and does not authorize.

## Executability rules
- No “could use”, “should consider”, “consider”, “maybe”, “improve hierarchy” or equivalent recommendation-only wording in `decision`.
- Repeated observations must be consolidated into one action.
- A screen-level review with more than one material issue must use at least two categories when evidence supports distinct categories.
- `evidence_anchor` must name the visible element or spatial relationship; generic labels such as `screen`, `UI`, `layout` or `page` are insufficient.
- All `evidence_component_ids` must exist in Component Tree.
- `execution.target_component_id` must exist and must be listed in `evidence_component_ids`.
- `implementation_change` and `acceptance_criteria` must mention target-specific concepts; long generic prose does not satisfy this contract.
- Category/operation and operation/check combinations must be compatible.

## Rubric binding
A PASS-like verdict is invalid if:
- total < 20/25;
- Layout precision = 0;
- Handoff quality = 0;
- any criterion lacks structured evidence refs + a substantive summary.

A score of 5 requires structural support in the relevant deliverable section; a generic evidence sentence cannot manufacture a 5.

## Semantic authority rule
Structural validity does not authorize a business-semantic claim.

The semantic judge must compare raw input/upstream constraints to the selected decision. It must fail structurally valid but semantically damaging actions, including:
- removing the wrong duplicate component;
- claiming debt closure from payment-registration evidence only;
- creating urgency/guarantee language not authorized by source;
- choosing a layout transformation that worsens the diagnosed relationship;
- dropping an adjacent upstream constraint while preserving only the visual structure.

For COPY/RISK/meaning-changing STATE actions, `semantic_authority` is mandatory. A conservative reduction of an unsupported claim is allowed only when it does not invent a stronger claim.

## Consistency rule
When the same screen/input reaches UI Architect through Router and direct profile activation, normalized `remediation_actions` must not materially diverge unless the input context differs. Routing metadata is not a reason to change UI decisions.

## LF safety
Existing LF visual governance remains mandatory. No pressure, fake urgency, dark patterns, aggressive debt cues or guaranteed outcomes may be introduced by a remediation action.