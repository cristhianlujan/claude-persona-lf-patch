# Sandbox Test Report — PATCH_LF_SKILL_PROFILE_PACK_STANDARD_001

Run ID: `SANDBOX_TEST_001_LOCAL_READ_ONLY`  
Timestamp UTC: `2026-05-23T05:36:50Z`  
Scope: local ZIP only. No GitHub, Supabase or ACT-0045 impact.

## ACT-0045 control

- estado_documental: VIGENTE
- estado_operativo: READ_ONLY
- runtime_estado: PRODUCCION_CONTROLADA_READ_ONLY
- impacto_automatico: BLOQUEADO

## Original sandbox result

Profiles: 4/4 passed  
Skills: 4/4 passed

Original restriction:
- `examples/self_repair_output.json` produced the right decision but did not validate against `schemas/output.schema.json` because `deliverable_created` was missing.

## Local self-repair applied

- Expanded validators to check all 22 required files.
- Added jsonschema validation for good and self-repair examples.
- Preserved bad examples as intentionally failing output schema.
- Made self-repair output schema-valid while preserving `BASIC_SKILL_OUTPUT_NOT_ACCEPTABLE`.

## Repaired sandbox result

Profiles: 4/4 passed  
Skills: 4/4 passed

### Cases

| Case | Expected | Profiles | Skills |
|---|---|---|---|
| `HAPPY_PATH_001` | `VALID_OUTPUT` | `VALID_OUTPUT` / PASS | `VALID_OUTPUT` / PASS |
| `MISSING_INPUTS_001` | `RETURN_TO_ORCHESTRATOR` | `RETURN_TO_ORCHESTRATOR` / PASS | `RETURN_TO_ORCHESTRATOR` / PASS |
| `UNSAFE_OR_BLOCKED_001` | `BLOCK_PIPELINE` | `BLOCK_PIPELINE` / PASS | `BLOCK_PIPELINE` / PASS |
| `SELF_REPAIR_001` | `RETURN_TO_WORKER_FOR_SELF_REPAIR` | `RETURN_TO_WORKER_FOR_SELF_REPAIR` / PASS | `RETURN_TO_WORKER_FOR_SELF_REPAIR` / PASS |

## Final verdict

`SANDBOX_PASS_READY_FOR_CONTROLLED_PR_PREP`

## Restrictions

- No GitHub write without explicit user approval.
- If approved, create only a controlled branch/draft PR first.
- No merge.
- No ACT-0045 modification.
- No Supabase modification except optional log with approval.
- Keep runtime general disabled and production general disabled.
