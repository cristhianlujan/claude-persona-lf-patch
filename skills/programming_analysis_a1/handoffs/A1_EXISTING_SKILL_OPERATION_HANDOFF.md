# A1 — Handoff de integración con EJECUCION_SKILL_LF

**Tipo:** preparación source-only. **Estado:** `BLOCKED_NOT_WIRED`. No implica ejecución real ni modificación de Router.

## Lectura canónica (Supabase, 2026-11-03)

- `public.lf_operation_registry`: `EJECUCION_SKILL_LF` v0.1, `SANDBOX_ACTIVE`.
- `public.lf_router_action_registry`: `SKILL_EXECUTION`, `ACTIVE`, exige target existente, `write_allowed=false`.
- `public.lf_operation_step_contracts`: `init_execution → router → skill_resolve → skill_source_read → input_validate → execute_skill → output_validate → semantic_judge → report_output`.
- `public.lf_operation_judges`: `JUDGE-EJECUCION-SKILL-LF-v0.1` tiene `pass_if=[]` y `fail_if=[]`; eso no acredita por sí mismo enforcement server-side de resultados `FAIL`.
- `public.lf_activos`: A1 `PROGRAMMING_ANALYSIS_A1` no registrada (0).
- `public.lf_operation_execution`: A1 bajo `EJECUCION_SKILL_LF` (0); 414 ejecuciones históricas de skills ajenas, no prueban A1.

## Integración propuesta

Perfil consumidor ya seleccionado → handoff autorizado → operación EXISTENTE `EJECUCION_SKILL_LF` → resolver fuente A1 CURRENT → `prepare` → invocar modelo por dueño del runtime → `evaluate_model_candidate` → juez realmente independiente → `validate_review` → recorder/ledger → lectura del recibo → perfil consumidor decide A2.

El paso `router` de la operación deberá **reutilizar/validar la autoridad del handoff existente**, no disparar un segundo encaminamiento; este comportamiento está **pendiente de comprobar** en el runtime real.

Contrato de mapeo: `adapters/existing_skill_operation_binding_v1.json`.

## Gates de integración

1. Registrar y liberar gobernadamente A1 como SKILL, con fuente y hash exactos.
2. Verificar autoridad y modo habilitado de la operación para consumir A1; no convertir `SANDBOX_ACTIVE` en `CURRENT RELEASED` por inferencia.
3. Demostrar dos invocaciones de modelo efectivas y separadas para productor y juez, ambas con recibos del proveedor/host y hashes. No aceptar `PASS` auto declarado.
4. Confirmar enforcement negativo: `semantic_judge=FAIL` y `unsupported_claims` no vacíos producen rechazo real; la existencia de llaves no basta.
5. Registrar/leer los recibos en el mismo RUN gobernado y solo entonces retornar resultado al perfil. Sin direct-call Router→skill y sin `service_role` en Router.

**No cerrar A1 como `SKILL_READY` ni `SKILL_INTEGRATED` con este handoff.** Ninguno de estos gates operativos se ejecutó aquí.
