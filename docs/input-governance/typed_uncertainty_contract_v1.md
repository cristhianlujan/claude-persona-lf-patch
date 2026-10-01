# M1.5 — Typed Uncertainty Contract v1

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M1.5` / `PAULO-120` / L4  
**Purpose:** type every current `PARTIAL`/blocker pattern with an explicit state, uncertainty type, blocking stage, and reproducible evidence envelope without changing runtime behavior.

## Authority and scope

- Current readiness contract: `INPUT_READINESS_CONTRACT` revision `5.13`.
- Current contract spec MD5 at readback: `1d9709b94d20ee8036ad985edffaaf01`.
- Implementation-dependency decision: `DEC-INPUT-GOV-IMPL-DEPENDENCY-001`, recorded by `lf_eventos#19725`, Git PR `#1369`.
- This unit is contract/readback only. It does not change classifier functions, Curator, Validator, runtime, deployment, promotion, or production.

## Current AS-IS readback

- `input_family_assessments`: 1,948 `PARTIAL`; **1,948/1,948 have blockers**.
- Total blocker elements across current persisted assessments: **5,300**.
- Distinct blocker codes: **120**.
- Distinct normalized pattern rows (`code + keyset + type + stage + state`): **161**.
- Untyped blocker elements: **0**.
- Untyped blocker codes: **0**.
- `PARTIAL` assessments with any untyped blocker: **0**.
- Blocking-stage unresolved elements: **0**.
- Evidence-envelope unresolved elements: **0**.
- Current blockers carrying a governed dependency reference (`dependency_ref`, `work_item_ref`, `platform_work_ref`): **0**.

Pattern-map SHA-256:

`71b2b5c8494be02e0bbdfed158d3e7ececcd896867c3585a15ec741389f90442`

## Contract schema

Every uncertainty record MUST resolve these fields:

| Field | Requirement |
|---|---|
| `state` | `BLOCKED`, `READY_WITH_DEPENDENCY`, or `INFORMATIONAL` |
| `uncertainty_type` | One governed type from the table below |
| `blocking_stage` | `STORY`, `IMPLEMENTATION`, `QA`, `PRODUCTION`, or `NONE` |
| `evidence` | Reproducible envelope containing at least `assessment_id`, `run_id`, `family_code`, and the original blocker payload |

`source_ref` is retained when present but is not required merely to preserve an observed blocker: the original blocker payload plus assessment/run/family identity is the minimum evidence envelope. A type-specific resolution MAY require stronger evidence before the uncertainty can be cleared.

## Governed uncertainty types

| Type | Current elements | Default state | Typical resolution evidence |
|---|---:|---|---|
| `MISSING_SOURCE` | 1,606 | `BLOCKED` | canonical source/ref or contract-authorized absence |
| `SOURCE_CONFLICT` | 49 | `BLOCKED` | conflicting refs + adjudication/precedence authority |
| `CANDIDATE_AUTHORITY` | 258 | `BLOCKED` | lifecycle/promotion authority proving usable current source |
| `DELIVERY_DEPENDENCY` | 250 | `BLOCKED` unless dependency rule passes | governed dependency reference + completion/readback |
| `INCOMPLETE_EVIDENCE` | 765 | `BLOCKED` | missing evidence needed by the family/stage contract |
| `QA_EVIDENCE_PENDING` | 356 | `BLOCKED` unless dependency rule passes | governed QA dependency + executed evidence/readback |
| `UNRESOLVED_SEMANTIC` | 241 | `BLOCKED` | semantic authority/resolution receipt |
| `HUMAN_DECISION_REQUIRED` | 109 | `BLOCKED` | explicit owner/decision authority |
| `POLICY_RECLASSIFICATION` | 611 | `INFORMATIONAL` | no additional evidence required to treat marker as informational |
| `IMPLEMENTATION_DEPENDENCY` | 721 | `BLOCKED` unless dependency rule passes | governed implementation/platform work reference + readback |
| `EXTERNAL_ARTIFACT_UNRESOLVED` | 48 | `BLOCKED` | directly resolvable artifact identity/digest or approved authority |
| `APPLICABILITY_AUTHORITY_MISSING` | 110 | `BLOCKED` | positive applicability / N-A authority |
| `PRODUCTION_AUTHORIZATION_MISSING` | 176 | `BLOCKED` | production authorization authority |

## Deterministic classification precedence

Apply the following rules in order; first match wins:

1. `R3_SEMANTIC_FAIL_CLOSED_RECLASSIFICATION` or `V59_STAGE_SPECIFIC_RECLASSIFICATION` → `POLICY_RECLASSIFICATION`.
2. `status=HUMAN_DECISION_REQUIRED`, `*_DECISION_REQUIRED`, `human_decision_required=true`, or `required_decision` present → `HUMAN_DECISION_REQUIRED`.
3. marker contains `CONFLICT` or `RECONCILIATION` → `SOURCE_CONFLICT`.
4. `PRODUCTION_NOT_AUTHORIZED` → `PRODUCTION_AUTHORIZATION_MISSING`.
5. candidate-not-ready / non-production source markers → `CANDIDATE_AUTHORITY`.
6. binary/visual external-resolution failures → `EXTERNAL_ARTIFACT_UNRESOLVED`.
7. applicability authority/scope unresolved markers → `APPLICABILITY_AUTHORITY_MISSING`.
8. semantic/subject/threat/component semantic unresolved markers → `UNRESOLVED_SEMANTIC`.
9. binding/provider/runtime/platform implementation dependency markers → `IMPLEMENTATION_DEPENDENCY`.
10. QA/E2E/validation/test-evidence pending or required markers → `QA_EVIDENCE_PENDING`.
11. missing/not-linked/source-incomplete/source-identification/canonical-missing/requirement-missing markers → `MISSING_SOURCE`.
12. remaining `PARTIAL`/`INCOMPLETE` markers → `INCOMPLETE_EVIDENCE`.
13. remaining `PENDING`/`NOT_READY`/`NOT_AUTHORIZED` markers → `DELIVERY_DEPENDENCY`.
14. No fallback-to-generic type is allowed. An unmatched marker is a contract defect and MUST fail closed.

## Blocking-stage precedence

Resolve `blocking_stage` in this order:

1. blocker `earliest_blocking_stage` when present;
2. explicit blocker flags: `blocks_story`, `blocks_implementation`, `blocks_qa`, `blocks_production`;
3. type override:
   - `POLICY_RECLASSIFICATION` → `NONE`;
   - `PRODUCTION_AUTHORIZATION_MISSING` → `PRODUCTION`;
   - `QA_EVIDENCE_PENDING` → `QA`;
   - `CANDIDATE_AUTHORITY` / `IMPLEMENTATION_DEPENDENCY` → `IMPLEMENTATION`;
   - `APPLICABILITY_AUTHORITY_MISSING` → `STORY`;
   - `EXTERNAL_ARTIFACT_UNRESOLVED` → `QA`;
4. otherwise use `INPUT_READINESS_CONTRACT 5.13.family_stage_requirements[family_code].coverage_required_by`.

Current derived stage distribution: `STORY=509`, `IMPLEMENTATION=3,285`, `QA=971`, `PRODUCTION=176`, `NONE=359`; unresolved=`0`.

## READY_WITH_DEPENDENCY guard

`DEC-INPUT-GOV-IMPL-DEPENDENCY-001` permits `READY_WITH_DEPENDENCY` only for a genuine implementation/platform dependency that no longer blocks story preparation.

A blocker MAY become `READY_WITH_DEPENDENCY` only when all conditions hold:

1. its type is `IMPLEMENTATION_DEPENDENCY`, `QA_EVIDENCE_PENDING`, or `DELIVERY_DEPENDENCY`;
2. it contains a governed `dependency_ref`, `work_item_ref`, or `platform_work_ref`;
3. the dependency is independently resolvable/readable and its lifecycle is explicit;
4. the uncertainty is **not** missing definition, pending owner decision, source conflict, unresolved semantic meaning, applicability authority absence, or incomplete contract/source authority;
5. later stages remain fail-closed: QA/production do not become ready merely because story preparation is allowed.

Current readback has **0/5,300** blocker elements with such a dependency reference, therefore this unit does **not** reclassify any existing blocker to `READY_WITH_DEPENDENCY`.

## Negative contract

- `PARTIAL` without a typed blocker → defect / fail closed.
- blocker without a governed uncertainty type → defect / fail closed.
- blocker without determinable blocking stage → defect / fail closed.
- `READY_WITH_DEPENDENCY` without governed dependency reference → defect / remain `BLOCKED`.
- owner decision, source conflict, semantic uncertainty, missing definition, or incomplete canonical authority MUST NOT be laundered into `READY_WITH_DEPENDENCY`.
- `POLICY_RECLASSIFICATION` is informational and MUST NOT by itself create readiness debt.

## Readback result

The deterministic rules above classify the current corpus with:

- blocker elements: `5300`
- distinct markers: `120`
- normalized pattern rows: `161`
- untyped elements: `0`
- untyped markers: `0`
- `PARTIAL` assessments with untyped blockers: `0`
- unresolved blocking stages: `0`
- unresolved evidence envelopes: `0`
- current `READY_WITH_DEPENDENCY` eligible blockers: `0`

No runtime behavior is changed by this contract.