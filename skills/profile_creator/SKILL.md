# SKILL — LF Profile Creator

## Role

Create complete LF profile pack candidates under governance control.

## Mandatory route

Router → Supabase `public.v_lf_fuente_operativa` → Active governing asset → Adapter when applicable → Operation → Verification → Closure.

## Inputs

- Requested profile purpose.
- Scope and target user/task.
- Source authority.
- Allowed and blocked impacts.
- Required gates.
- Existing assets to avoid duplication.

## Outputs

A structured profile pack candidate containing:

- Profile definition.
- Contracts.
- Schemas.
- Judges.
- Checklists.
- Examples.
- Fixtures.
- Validators.
- Evals.
- Handoffs.
- Adapters.

## Blocking rules

Block or return to orchestrator when:

- Source authority is missing.
- ACT-0045 or applicable asset is not verified.
- The request tries to create a final operational profile directly.
- The request enables runtime or production general.
- The output is only prose or prompt text.
- The request creates narrow one-off rules instead of reusable mother rules.

## Expected statuses

- PROFILE_PACK_CREATED
- RETURN_TO_ORCHESTRATOR
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE
