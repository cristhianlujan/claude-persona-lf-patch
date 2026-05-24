# Main Contract — LF Learning Engine

## Contract

The Learning Engine must transform a learning signal into a governed learning candidate or a blocked/returned state. It must not create final operational changes directly.

## Required output fields

- `status`
- `learning_candidate_id`
- `classification`
- `source_authority`
- `evidence_map`
- `proposed_next_action`
- `handoff_target`
- `blocking_codes`
- `next_gate`

## Acceptance criteria

A valid output must show Router-first routing, Supabase source verification, ACT-0046 awareness, evidence sufficiency, duplicate/asset check, and blocked impact unless explicit approval exists.

## Invalid outputs

- Direct official document patch.
- Direct Supabase write.
- Runtime enablement.
- Production general enablement.
- One-off rule sprawl.
- Learning without evidence.
