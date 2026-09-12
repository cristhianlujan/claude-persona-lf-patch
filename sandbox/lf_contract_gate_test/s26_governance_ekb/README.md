# S26-E Governance / EKB / Card fallback evidence

Base verified before materialization: `d75b7c15dac66ed9ae9f7b1cf78fb8ee3872d921`.

## Existing authority readback

`CONTRACT-PRE-EKB-GATE-LF-v0.1` already exists and is `ACTIVE_ENFORCEMENT` for ACT-0052..ACT-0058. S26-E does not recreate it.

The live EKB readback is materialized in `s26_e_preexecution_evidence_v2.json`. Its `payload_digest` is the canonical SHA-256 of the `payload` object and is revalidated by the judge before execution can pass. The snapshot covers all seven minimum rule codes required by the existing PRE-EKB contract:

- `CI-E16-001`
- `CI-MIG-001`
- `DB-001`
- `DB-EVT-001`
- `GOV-010`
- `KB-PROD-001`
- `OPS-002`

The committed pre-execution receipt must classify every minimum rule as `APPLICABLE` or `NOT_APPLICABLE`, with evidence; every applicable rule requires a control.

## Card resolver evidence

The base `cards/` inventory contains two observed card families. The resolver reviewed:

- `cards/marketplace_lf/decision_product_experience/CARD.md`
- `cards/learning_competitive/campanas_y_ofertas/CARD.md`

Neither is compatible with the S26-E governance/EKB/applicability surface, so the actual resolver outcome is `NONE`. This is not treated as manual automatically.

## Actual fallback for this lane

The actual receipt selects the first governed fallback: `CONTRACT_SCHEMA`, because the existing `CONTRACT-PRE-EKB-GATE-LF-v0.1` is active. It does not falsely mark that alternative as failed.

| Card resolver result | Required continuation | Manual |
|---|---|---|
| EXACT | Use exact governed Card | No |
| COMPATIBLE | Use only with compatibility evidence | No |
| NONE + contract/schema | Use existing contract/schema | No |
| NONE + generic capability | Use reusable generic capability | No |
| NONE + safe composition | Use safe composition | No |
| NONE + all three safe alternatives fail with evidence | Stop and route manual | Yes, last resort |
| AMBIGUOUS | Fail closed | No automatic manual bypass |

## Canonical judge chain

The canonical entrypoint is `gobernanza/judges/validate_s26_governance_ekb_gate_strict.py`. It executes the base evaluator and adds integrity guards. Both layers are required by contract v0.3.

The base evaluator validates EKB snapshot integrity, all minimum rule classifications, provenance, Card state, fallback order, schema non-invention and learning persistence eligibility. The strict layer additionally proves that EXACT/COMPATIBLE Card references resolve to real files under `cards/` and forces `manual_allowed=false` whenever any blocker exists.

Top-level `NOT_APPLICABLE` is non-executable. Learning persistence remains independent from execution permission: incomplete or unverifiable provenance denies persistence without inventing evidence.

The canonical self-test covers 22 cases: the original 20 governance/fallback/provenance cases plus nonexistent Card rejection and manual-route rejection when exhaustion evidence is unresolved.
