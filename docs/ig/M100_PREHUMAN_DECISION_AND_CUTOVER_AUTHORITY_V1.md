# IG M10.0 — Pre-human decision gate versus operational cutover authority

**Scope:** `IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.0`, `PAULO-159`, only this proposed technical contract migration in PR #2355.  
**Status:** Candidate in draft, not applied. No change to any global judge, queue, runtime or production.

## Root cause

The old M10.0 checkpoint `HUMAN_DECISION_RECORD` required an actual `CUTOVER_AUTHORIZED` human receipt to mark sandbox engineering complete. This conflated:

1. a **technical proof** that authorization controls reject missing or forged approval;
2. classification of **IG diagnostic gaps** that might be resolved automatically or require a person; and
3. **actual operational promotion**, for which a governed human receipt is explicitly required by the existing `programacion.promotions` guard.

A classifier's `REQUIERE_DECISION` result is not an approval, and a technical receipt `PASS` does not automatically activate anything.

## Existing current capacities (runtime Supabase readback)

| Capability | Readback version | Role |
|---|---|---|
| `SAFE_CHANGE_ADMISSION` | 1.0.2 | `AUTOMATIZABLE`, `RECOMENDADA`, `REQUIERE_DECISION`, `VERIFY_NO_CHANGE`, `UNKNOWN`; never executes an effect |
| `HUMAN_ESCALATION_ADMISSION` | 1.0.4 | Pre-human gate: `NO_HUMAN_REQUIRED`, `AUTO_RESOLVE_FIRST`, `AUTO_EXECUTION_ELIGIBLE`, `ACQUIRE_EVIDENCE`, `EVIDENCE_REQUIRED`, `HUMAN_ELIGIBLE`, `BLOCKED`, `BLOCKED_NO_HUMAN` |
| `TARGETED_EVIDENCE_ACQUISITION` | 1.0.0 | Plan the next decision-changing evidence; does not collect it by itself |

The migration **does not hard-code these versions** as authority. Its preflight reads the current registry and checks compatible dependencies, active IG escalation policy, and the requirement that only `HUMAN_ELIGIBLE` admits the human queue. If current authority changes before Train runs, fail closed rather than simulate an approval.

## Decisions and responses

| Operational event | Correct next step | Human queue? |
|---|---|---|
| Deterministic rule is applicable and passes, or outcome is NOT_APPLICABLE | `NO_HUMAN_REQUIRED` | No |
| Proven resolver can address the issue | `AUTO_RESOLVE_FIRST` | No |
| Safe change classified `AUTOMATIZABLE` with downstream permission | `AUTO_EXECUTION_ELIGIBLE` (executor and governance still required) | No |
| More evidence may decide the case | `ACQUIRE_EVIDENCE` / `EVIDENCE_REQUIRED` | No |
| Recommendation without automatic permission (`RECOMENDADA`) | Look for decision-changing evidence; do not map directly to HUMAN | No by default |
| Unknown/missing current authority or failed evidence | Block / internal remediation; do not invent human eligibility | No by default |
| Policy admits human escalation after justified exhausted automation or legitimate specialist prequalification | `HUMAN_ELIGIBLE` | Yes, with verified reviewer authority |
| Actual cutover/promotion protected by `programacion.promotions` | Separate release authorization, exact `APPROVE` human receipt, verified manifest and independent audit | Mandatory for **this** operational action; **not** M10.0 CP5 |

This table describes existing technical governance, not proof that every LF B2B workflow consumes the gate. It also does not make M10.0 the owner of the transversal classifier.

## Specific IG integration

For an `INPUT_GAP_PROPOSAL`, the existing IG adapter `private.fn_lf_human_decision_open_ig_v3` must evaluate `private.fn_lf_ig_human_decision_live_disposition_v1` (live canonical state/currentness) before `HUMAN_ESCALATION_ADMISSION`. A historical `HUMAN_DECISION_REQUIRED` flag never suffices. `FEATURE_FLAG_CANONICAL_SOURCE_INCOMPLETE`, `BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL`, and `APPLICABILITY_AUTHORITY_REQUIRED` are active, exact IG policy reasons; there is no general ANY rule for IG.

The distinction between a missing semantic owner decision and **authorization to promote an already owner-approved candidate** is governed separately. Never infer the latter from candidate status.

## M10.0 engineering contract, CP5–CP7

- **CP5:** prove authority guards, signed provenance and absence of an unapproved promotion. **No live human decision** is created as proof.
- **CP6:** test real canonical positive receipt and five negative receipt-verifier cases; check actual database decision/HEAD constraints and enabled triggers. Do not use synthetic PASS.
- **CP7:** exact readback of signed upstream identities, technical evidence and blocked operational gate.
- **Operational admission (independent):** still requires real `APPROVE`, `CUTOVER_AUTHORIZED`, exact Git head SHA-1 and signed bundle SHA-256, actual human authority receipt and independent audit. This separate requirement cannot be waived by `SAFE_CHANGE_ADMISSION`.

Contract/governance are updated **together** in `engineering_plan_units`, `engineering_work_items` and CP action_specs + source_pack by the *single candidate migration*. Old work/exit/governance semantics are preserved in a metadata snapshot, while the active engineering phase is sandbox-only.

## Train / evidence boundary

- **Owner decision 2026-10-13:** PR #2355 is an **independent new changeset** eligible for existing scoped LF Migration Merge Train. Its application does **not** depend on retiring the historical unapplied SQL. Train must still validate the new PR, source identity, current prestate, exact ledger version and real DB readback.
- Historical premerged, never-applied `20261012223000_ig_m100_sandbox_technical_vs_operational_authority_v1.sql` (blob `dbe466b827f10c257dba6449d65d6750f2328057`) **stays in Git**. It is **technical debt, not a checkpoint dependency**, tracked by issue #2357; do not stamp its ledger, replay its SQL or change its blob to manufacture parity.
- PR #2356 attempted retirement through a source-only lane not currently supported by Train. Its merge is not required for M10.0; leaving it open must not hold PR #2355 in DRAFT.
- No agent may apply SQL or edit a credential-reading workflow to bypass Train.
- A GitHub PASS, a draft PR, or this document is not evidence of checkpoint DONE. Only Train's exact SQL+ledger+DB readback and canonical transitions can change M10.0 from 60%.
- Read-only connector calls to `lf_human_escalation_admission_v1` may be denied by ACL; such denial is not an admissible test PASS and must not be retried with elevated credentials.

Relevant EKB: `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`, `IG-TARGETED-EVIDENCE-BEFORE-HUMAN-ESCALATION-001`, `HUMAN-ESCALATION-CANDIDATE-PROMOTION-AUTHORITY-001`, `HUMAN-ESCALATION-IG-LATEST-RUN-NOT-CURRENT-001`, `IG-M99-REPETITIVE-SYMPTOM-PATCHING-001`, `CI-MIGRATION-SOURCE-PARITY-001`.
