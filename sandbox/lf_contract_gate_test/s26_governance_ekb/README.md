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

## Judge hardening

The validator fails closed for malformed receipt structures, invalid/non-canonical snapshot digests, missing minimum EKB rules, unknown/non-active rule codes, invalid Card candidate shapes, malformed fallback attempts, skipped fallback order and unresolved evidence references.

Top-level `NOT_APPLICABLE` is non-executable. Learning persistence remains independent from execution permission: incomplete or unverifiable provenance denies persistence without inventing evidence.

The self-test covers 20 cases, including the ten handoff minimums plus critical ambiguity, missing PRE-EKB authority, skipped fallback order, invalid digest, missing minimum rule, malformed EKB/fallback shapes, invalid Card candidate shape, top-level non-applicability and malformed receipt shape.
