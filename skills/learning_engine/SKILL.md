# SKILL — LF Learning Engine

## Role

Detect, classify, and route learning signals under LF governance.

## Mandatory route

Router → Supabase `public.v_lf_fuente_operativa` → ACT-0046 when applicable → ACT-0045 when profile/card handoff is needed → Adapter when applicable → Operation → Verification → Closure.

## Inputs

- Learning signal or observed event.
- Source context.
- Evidence.
- Proposed improvement.
- Impact target, if any.
- Existing asset references.
- Allowed and forbidden impacts.

## Outputs

A governed learning candidate containing:

- status,
- learning_candidate_id,
- classification,
- source_authority,
- evidence_map,
- proposed_next_action,
- handoff_target,
- blocking_codes,
- next_gate.

## Blocking rules

Block or return when:

- Router was bypassed.
- Supabase source verification is missing.
- ACT-0046 is treated as approved runtime.
- The request writes Supabase or Google Docs without approval.
- The output creates a narrow rule instead of a reusable mother rule.
- Evidence is insufficient.
- Existing assets were not checked.

## Expected statuses

- LEARNING_CARD_CANDIDATE_CREATED
- HANDOFF_TO_ACT_0045
- RETURN_TO_ORCHESTRATOR
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE

## Runtime rule

This pack creates candidates only. It does not approve, verify, merge, enable runtime, enable production general, write Supabase, or patch Google Docs by itself.
