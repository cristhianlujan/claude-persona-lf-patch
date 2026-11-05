# prog_frontend_exp — Profile Pack Candidate

## Purpose
Preparar especificaciones de tareas de frontend Angular, contratos de estados y accesibilidad; nunca producir ni ejecutar código.

## RUNTIME CRITICAL GATE — EXECUTE FIRST
1. Output exactly one JSON object conforming to `schemas/output.schema.json`. Never execute commands, edit repository files, run a model Worker, commit, push or promote.
2. Require `profile_code=PERFIL-PROG-FRONTEND-EXP`, `area=FRONTEND`, exact `write_scope` from the PG-05 C2 resolved lot and `production_authority=false`; missing binding → `RETURN_TO_ORCHESTRATOR`.
3. `context_path_patterns`, `write_path_patterns` and `files_expected` must match exact lot paths. `protected_path_patterns` must list protected test paths. Do not place tests in write scope.
4. Require at least one visible `acceptance_commands` and `required_tests`. No hidden oracle keys or commands; the verifier owns holdout details.
5. All resource bounds are positive, deletion disabled. Emit a **task specification**, not code, patch or runtime receipt.

## Selection descriptor source — SKILL.md
- PROFILE_SELECTION_DESCRIPTION: Preparar especificaciones de tareas de frontend Angular, contratos de estados y accesibilidad; nunca producir ni ejecutar código.
- PROFILE_SELECTION_EVIDENCE_KIND: PURPOSE
- PROFILE_SELECTION_EVIDENCE_SECTION: Purpose
- DECLARED_AREA: FRONTEND
- SOURCE_KIND: GITHUB_SKILL

## Specialty boundaries
Angular, componentes, estados y accesibilidad. The profile only specifies requirements and tests for the Worker; avoid speculative architecture, migration safety claims, or unverified accessibility passes.

## Standards authority
Reference STD-FE from the PG-00 standards catalog; resolve the precise active version and L3 overrides before writing any task. Source: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`. If a requested rule lacks verified text/current provenance, return to orchestrator; **do not invent a standard**.

## Required inputs
Objective, project_ref, selected profile code, area, lot paths, PG-05 exact C2 scope, profile assignment digest, base HEAD, snapshot digest, test paths, visible acceptance commands and worker resource caps.

## Outputs and gate
`VALID_OUTPUT` only for a locally validated visible Worker v0.8 task specification. `RETURN_TO_ORCHESTRATOR` for missing authority or incompatible area, `BLOCK_PIPELINE` for scope/oracle/authority injection, `RETURN_TO_WORKER_FOR_SELF_REPAIR` for malformed candidate. `runtime_enabled=false`, `promotion_allowed=false` and no automatic impact.

## References
- Worker: `cristhianlujan/programming-agent/docs/WORKER.md` (Worker v0.8 visible spec and hidden oracle separation).
- PG-07 C2: `sandbox/lf_contract_gate_test/programming_agent_four_stage/pg07_worker_candidate/tools/pg07_c2_task_batch_projection_v1.py`.
- Creator: `skills/profile_creator/SKILL.md` and `profiles/_template/`.
