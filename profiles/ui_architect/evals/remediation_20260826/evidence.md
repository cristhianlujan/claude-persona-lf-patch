# UI Architect remediation evidence — 2026-08-26

Status: CANDIDATE / SANDBOX / NO_RUNTIME / NOT_INDEPENDENT_SEMANTIC_REVIEW

## Scope
Profile: `profiles/ui_architect`
Base: `main@7ec2b3a7e3b55b5b8c606cc01d726a2edae3bfb1`
Branch: `lf/ui-architect-remediation-20260826`

## BEFORE evidence
### Case 1 — home_ruta_claridad_001
Existing repository output declared `output_type=UI_SECTION_SPEC`, used a non-canonical 25-point score (`product_alignment`, `visual_structure_clarity`, `constraint_preservation`, `handoff_readiness`, `cognitive_load_control`) and was passed by the historical mini-judge.

The current profile contract allows Production UI Spec / Focused UI Decision Spec / Missing Input State, and the canonical rubric is Layout precision / Visual hierarchy / LF system fidelity / State mapping / Handoff quality. Therefore the historical PASS is a reproducible contract/judge false positive.

Expected deterministic result after remediation: REJECT.

### Case 2 — checkout_direct_001
Materialized from observed direct profile review on 2026-08-26. It reports duplicate amount, sticky summary/alignment and distant method/CTA, but remains a generic review object without executable anchors, implementation changes or acceptance criteria.

Expected deterministic result after remediation: REJECT.

### Case 3 — checkout_router_001
Materialized from observed Router→UI review of the same checkout screen. It repeats materially the same generic findings.

Expected deterministic result after remediation: REJECT.

The checkout BEFORE fixtures are reconstructed from observed project-chat output; they are not represented as GitHub/runtime executions.

## Candidate change
1. Add `contracts/existing_screen_review.md`.
2. Existing-screen review remains `PRODUCTION_UI_SPEC`; no fourth mode is introduced.
3. Require `remediation_actions` with `issue_id`, priority, category, evidence anchor, selected decision, implementation change and visual acceptance criteria.
4. Add deterministic `validators/validate_ui_architect_output.py`.
5. Validate canonical score keys + evidence per criterion.
6. Harden mini-judge to fail when deterministic gate fails.
7. Require Router/direct consistency for the same material input.

## AFTER evidence
### Checkout
The AFTER outputs convert the observed findings into four executable actions:
- HIERARCHY: remove duplicate amount strip; summary becomes the sole payable-amount source.
- LAYOUT: align summary with first payment-method card; sticky top offset 24px.
- INTERACTION: CTA disabled until a method is selected; summary mirrors selected method before enabling CTA.
- COPY: one `Hoy pagas` label in summary; no repeated total-payment copy.

Risk controls preserve LF rules: no urgency banner, countdown, pressure copy or hidden fees.

Direct and Router AFTER fixtures contain identical normalized `remediation_actions`.

### Ruta de Claridad
The AFTER output uses `PRODUCTION_UI_SPEC`, a real Component Tree, the canonical score dimensions with evidence, explicit state/token/layout fields and a structured handoff.

## Executed preflight
Local candidate preflight executed against the same validator code before publication:
- `before_checkout_direct_001.json` → EXPECTED_REJECT
- `before_checkout_router_001.json` → EXPECTED_REJECT
- `after_home_ruta_claridad_001.json` → PASS
- `after_checkout_direct_001.json` → PASS
- `after_checkout_router_001.json` → PASS
- direct/router remediation actions equality → PASS

Result: 6/6 local checks PASS.

The branch includes `profiles/ui_architect/evals/remediation_20260826/run_cases.py`, which also targets the exact historical repository output and expects it to be rejected. That exact branch runner has not been executed by GitHub CI in this change because the existing global workflow was not modified.

## Root-cause classification
- Profile-specific: existing-screen reviews lacked a mandatory action-level remediation contract.
- Profile creation pattern: profile artifacts could be internally inconsistent (SKILL/contract/rubric vs stored run/judge) while still looking complete.
- Eval/judge: mini-judge accepted a stale output mode and stale score taxonomy.
- Router/governance: not root cause of the UI decision quality; same-input Router/direct consistency is now an explicit check.

## Root fix candidate for profile_creator
The reusable control is a cross-artifact consistency gate: generated profiles must prove that allowed output modes, schema, score rubric, mini-judge and positive/negative fixtures agree on the same vocabulary and required fields. A stored output that uses an undeclared mode or stale rubric must be rejected.

Do not write this root fix from this branch because `skills/profile_creator/**` is concurrently owned by PRs #236/#237 and requires the CREACION_SKILL_LF authority path.

## Governance path conflict
PR #238 exact-head CI demonstrated that the profile traceability requirement (`sandbox_runs/ui_architect/<case_id>/`) conflicts with the current global contract-check allowlist, which governs `profiles/**` but rejects `sandbox_runs/**` with `FAIL_SCOPE_INVALID`. This is recorded in EKB as GOV-022.

To keep this remediation within its authorized profile scope, the candidate fixtures and evidence live under `profiles/ui_architect/evals/remediation_20260826/**`. This does not silently redefine the canonical traceability path; promotion to `sandbox_runs/**` remains a governance issue outside this lot.

## Claim boundary
This evidence supports `CANDIDATE_FIX_STRUCTURALLY_VERIFIED` for the UI profile changes. It does not claim `REMEDIATED_VERIFIED`, independent semantic review, runtime activation, production authorization, canonical source promotion or completed root-fix integration in `profile_creator`.
