# Contract — Existing Screen Review / Remediation V5

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
- `precision_basis`: required whenever a material action specifies spacing, size, state behavior or another implementation value.
  - `mode`: one of `CANONICAL_TOKEN`, `UPSTREAM_VALUE`, `EXPLORATORY_PROPOSAL`, `RELATIVE_GUIDANCE`.
  - `source_refs`: required for `CANONICAL_TOKEN` or `UPSTREAM_VALUE`; may be empty for an explicitly exploratory proposal.
  - `value_or_rule`: exact token/value when known, or the proposed/relative rule when not canonical.
  - `proposal_status`: `NOT_APPLICABLE` for canonical/upstream values; `PROPOSED_NOT_CANONICAL` for exploratory values.

## Context resolution before deciding
The profile is not entitled to treat the user prompt as the entire available context. Before fixing a material detail it must consume the relevant context already supplied or resolved by the orchestrator, including when applicable:
- design-system tokens;
- component/state contracts;
- interaction rules;
- upstream product/UX constraints;
- frozen shell/delta boundaries;
- visible source facts from the screen itself.

Use this resolution ladder:
1. **Canonical value exists** → use it explicitly in the action/report and bind the source. Example: `payment_amount -> divider = space_24`, not merely `dar más aire`.
2. **Upstream/user value exists but is not a DS token** → use the exact supplied value and label it `UPSTREAM_VALUE`.
3. **No canonical value exists and the task is exploratory or the choice is low-risk** → continue. Choose a concrete proposal when useful, mark it `EXPLORATORY_PROPOSAL`, or use `RELATIVE_GUIDANCE` if exact units would create false precision. Absence of a token alone is never a reason to block exploration.
4. **Missing information would materially change interaction semantics, business meaning, safety, or a protected constraint** → return the missing input to the orchestrator under `contracts/missing_input_policy.md`; do not silently invent it and do not ask the end user directly from the worker.

The orchestrator should attempt canonical repo/Supabase/upstream resolution before escalating a material question to the user. The profile must not request information that is already recoverable from supplied canonical context.

## Compact report rule
User-facing review output should remain compact; precision does not mean producing a super-report.

For each material finding, the visible report should communicate:
- **Observation** — what is visibly wrong or weak.
- **Selected correction** — one implementation-ready change.
- **Precision basis** — exact canonical/upstream value when known, or an explicitly labeled proposal/relative rule when not canonical.

Do not dump internal schema, EKB, judge metadata or every available token into the user-facing report. Include only context that changes or constrains the correction.

Examples:
- Canonical: `Monto muy cerca del divisor → payment_amount → divider = space_24 (DS)`.
- Exploratory: `Monto muy cerca del divisor → aumentar un nivel la separación; 24px puede usarse como propuesta inicial, no como token canónico`.
- Material unresolved: `Comportamiento CTA sin selección → RETURN_TO_ORCHESTRATOR: resolver interaction contract; no asumir disabled/active`.

## Executability rules
- No “could use”, “should consider”, “consider”, “maybe”, “improve hierarchy” or equivalent recommendation-only wording in `decision`.
- Repeated observations must be consolidated into one action.
- A screen-level review with more than one material issue must use at least two categories when evidence supports distinct categories.
- `evidence_anchor` must name the visible element or spatial relationship; generic labels such as `screen`, `UI`, `layout` or `page` are insufficient.
- All `evidence_component_ids` must exist in Component Tree.
- `execution.target_component_id` must exist and must be listed in `evidence_component_ids`.
- `implementation_change` and `acceptance_criteria` must mention target-specific concepts; long generic prose does not satisfy this contract.
- Category/operation and operation/check combinations must be compatible.
- When canonical precision is available, generic language such as `dar más aire`, `subir levemente`, `mejorar spacing` or `ajustar densidad` is insufficient unless the same action also binds the exact token/value.
- An exploratory proposal must never be presented as a canonical DS rule or upstream requirement.

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
- dropping an adjacent upstream constraint while preserving only the visual structure;
- presenting an exploratory value as canonical authority;
- ignoring a canonical token/interaction rule that was available in supplied context and materially changes the handoff.

For COPY/RISK/meaning-changing STATE actions, `semantic_authority` is mandatory. A conservative reduction of an unsupported claim is allowed only when it does not invent a stronger claim.

## Consistency rule
When the same screen/input reaches UI Architect through Router and direct profile activation, normalized `remediation_actions` must not materially diverge unless the input context differs. Routing metadata is not a reason to change UI decisions.

## LF safety
Existing LF visual governance remains mandatory. No pressure, fake urgency, dark patterns, aggressive debt cues or guaranteed outcomes may be introduced by a remediation action.
