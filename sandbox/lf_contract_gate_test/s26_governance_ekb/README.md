# S26-E Governance / EKB / Card fallback evidence

Base verified before materialization: `d75b7c15dac66ed9ae9f7b1cf78fb8ee3872d921`.

## Existing authority readback

`CONTRACT-PRE-EKB-GATE-LF-v0.1` already exists in `supabase/migrations/20260824071146_lf_pre_ekb_gate_operation_contracts_v1.sql` and is consumed by the governed EKB writer in `supabase/migrations/20260825063529_lf_pipeline_ekb_writer_event_origin_governance_v1.sql`. S26-E does not recreate it.

## Card / no-Card matrix

| Card resolver result | Required continuation | Manual |
|---|---|---|
| EXACT | Use exact governed Card | No |
| COMPATIBLE | Use only with compatibility evidence | No |
| NONE + contract/schema | Use existing contract/schema | No |
| NONE + generic capability | Use reusable generic capability | No |
| NONE + safe composition | Use safe composition | No |
| NONE + all three safe alternatives fail with evidence | Stop and route manual | Yes, last resort |
| AMBIGUOUS | Fail closed | No automatic manual bypass |

## Proofs

The validator self-test covers the ten handoff-required cases plus critical applicability ambiguity and missing PRE-EKB authority. The committed positive receipt proves a `NONE -> GENERIC_CAPABILITY` path where manual is correctly avoided. Self-test case `05_manual_last_resort` proves manual is permitted only after contract/schema, generic capability and safe composition all fail with evidence.

Learning persistence is independent from execution permission: insufficient provenance denies persistence without inventing evidence; complete verified provenance makes the learning eligible for persistence.
