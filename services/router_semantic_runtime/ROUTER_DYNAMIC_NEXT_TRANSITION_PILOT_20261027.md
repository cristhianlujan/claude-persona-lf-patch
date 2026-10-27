# ACT-0001 dynamic next-transition pilot — 2026-10-27

This extends the existing candidate operation `EJECUCION_ROUTER_LF` from three to four governed steps:

1. `request_intake`
2. `stage1_seal`
3. `stage2_route`
4. `resolve_next_transition`

The fourth step is deterministic. It reads the sealed `route_result` from the same execution and maps the current ACT-0001 `paso` to the next governed state. The caller never supplies `route_result` or `next_step`.

Current transition map:

| Stage2 paso | transition_code | class | next_step |
|---|---|---|---|
| PRODUCTO_PROFILE_SELECTION_REQUIRED | PROFILE_SELECTION_REQUIRED | CONTINUE | profile_semantic_selection |
| PROGRAMACION_PROFILE_SELECTION_REQUIRED | PROFILE_SELECTION_REQUIRED | CONTINUE | profile_semantic_selection |
| OPERACIONES_PROFILE_SELECTION_REQUIRED | PROFILE_SELECTION_REQUIRED | CONTINUE | profile_semantic_selection |
| DIRECT_ANSWER | DIRECT_RESULT | TERMINAL | result_direct |
| ASK_USER | CLARIFICATION_REQUIRED | WAIT_USER | clarification |
| MULTINEGOCIO_PENDIENTE | BUSINESS_AUTHORITY_REQUIRED | WAIT_GOVERNANCE | business_authority |
| NEGOCIO_NO_HABILITADO | BUSINESS_NOT_ENABLED | BLOCKED | blocked_business |
| RUTA_TRANSVERSAL_GESTION_ACTIVOS_IA | TRANSVERSAL_GOVERNED_OPERATION_REQUIRED | HANDOFF | transversal_governed_operation |
| PROPUESTA_PERFIL | PROFILE_PROPOSAL_REQUIRED | CONTINUE | profile_proposal |
| CANDIDATO_UNICO | IDENTITY_CONFIRMATION_REQUIRED | CONTINUE | identity_confirmation |
| ELEGIR_O_PROFUNDIZAR | CANDIDATE_DISAMBIGUATION_REQUIRED | CONTINUE | candidate_disambiguation |
| NIVEL_2_CONSENTIMIENTO | LEVEL2_CONSENT_REQUIRED | WAIT_USER | level2_consent |
| NIVEL_2_RESULTADO | LEVEL2_RESULT_READY | CONTINUE | level2_result |
| INVALID_STAGE1 / INVALID_STAGE1_V2 | INVALID_STAGE1_BLOCKED | BLOCKED | blocked_invalid_stage1 |
| SYSTEM_NOT_SUPPORTED / DISPATCHED | LEGACY_ROUTE_FORBIDDEN | BLOCKED | blocked_legacy_route |

Any unrecognized `paso` fails closed with `BLOCK_ROUTER_ROUTE_STEP_UNMAPPED`.

Security / sequence properties:
- `lf_router_pipeline_resolve_next_transition_v1` is internal-only; service_role and read-only identities cannot invoke it.
- `lf_router_route_transition_resolve_v1` is internal-only.
- `lf_router_pipeline_stage2_continue_v1` automatically invokes the transition resolver after Stage2 is sealed.
- `lf_router_execution_trust_validation_v1` recomputes the expected transition server-side.
- The generic recorder cannot accept a fabricated transition even when caller trust says `valid=true`.
- The operation remains `CANDIDATO_READ_ONLY / OP_CANDIDATE`; no Router cutover or effect authority is introduced.
