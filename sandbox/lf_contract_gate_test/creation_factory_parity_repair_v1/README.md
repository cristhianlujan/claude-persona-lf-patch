# Creation Factory Parity Repair V1

Status: CANDIDATE / NOT APPLIED / NO MERGE

## Root cause

The governed creation factories evolved unevenly.

- CREACION_PERFIL_LF had complete step-contract-judge-binding coverage.
- CREACION_CARD_LF had 39 active steps but only 19 active enforcement bindings.
- CREACION_SKILL_LF had 38 active steps but only 18 active enforcement bindings.
- Card and Skill were missing the same 20 judge/binding families.
- Skill additionally drifted between Git-first source and Supabase: write/readback appeared before its pre-write gate in the effective materialization, and partial-scope/depth gates were not coherently represented.

The defect is therefore not a missing Card recorder in isolation. It is incomplete factory materialization plus missing parity admission.

## Repair

The candidate:

1. Restores the Git-first Skill validation topology.
2. Adds a factory parity guard requiring exactly one active contract, binding and judge per active step.
3. Reconciles missing judges/bindings only under a real IN_PROGRESS execution of the same factory operation, preserving provenance.
4. Adds server-derived trust validation.
5. Adds a common creation-factory recorder over lf_record_operation_step_core_v1.
6. Adds thin Card and Skill wrappers.
7. Binds Skill pre-write -> write -> readback through an exact write plan, commit/blob evidence and file-set parity.
8. Leaves CREACION_PERFIL_LF unchanged and uses it only as a parity reference.

## Dry-run evidence

Executed against live authority inside BEGIN/ROLLBACK after compiling the candidate migration:

- Card parity: 39/39 contracts, 39/39 bindings, 39/39 judges — PASS.
- Skill parity: 39/39 contracts, 39/39 bindings, 39/39 judges — PASS.
- Profile parity: 40/40 unchanged — PASS.
- Card router step: STEP_CLEAN_PASS.
- Skill init_execution: STEP_CLEAN_PASS.
- Skill router step: STEP_CLEAN_PASS.
- Skill pre-write with exact write-plan hash: PASS.
- Skill pre-write with altered hash: BLOCK.
- Card github_write before pre-write/prior required steps: BLOCKED with PRIOR_REQUIRED_STEP_NOT_CLEAN.
- Transaction rolled back; no production mutation was retained.

## Non-goals

- No card is created by this repair.
- No runtime or production activation.
- No profile behavior changes.
- No merge.
- No parallel factory engine.
