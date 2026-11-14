# EJECUCION_PERFIL_LF — plan genérico desde BD (candidato DRAFT · NO-GO)

## Disparo único visible al dueño
> Ejecuta EJECUCION_PERFIL_LF para <solicitud + contexto>

El dueño **no** selecciona perfil ni skills, no enumera pasos ni opera transporte.

## Definición interna de operación (no forma parte del disparo)
- El Router ACT-0001 clasifica/selecciona exclusivamente un PERFIL y transporta Gate2 íntegro; no elige ninguna skill. El chat GPT nativo propietario ejecuta su RUN `EJECUCION_PERFIL_LF` con el mismo `execution_id` y ninguna API externa de modelo.
- Planificador candidato `public.lf_profile_execution_plan_v1(p_profile_code)` en `supabase/migrations/20261114020000_lf_profile_step40_ig_profile_owned_v1.sql`: consulta `public.lf_operation_steps` + `public.lf_operation_step_contracts` (11 ACTIVE_ENFORCEMENT verificados) para obtener secuencia, `resolver_ref`, requisitos y transiciones. **No acepta lista de pasos o skills del usuario.**
- Skills disponibles se resuelven desde `public.lf_activo_relaciones` (vínculo ejecutable `USA_SKILL`) y `public.lf_skill_catalog_v1` (`required_operation='EJECUCION_PERFIL_LF'`, `status='READY'`, `effect IN ('READ_ONLY','PROPOSE_ONLY')`). Los pasos 40 y 50 son **genéricos**: consumen el plan y las herramientas de perfil vinculadas, sin codificar IG en su definición candidata.
- El transporte oficial interno ya existente sigue `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1` / `LF_PROFILE_NATIVE_RESUME_REQUEST_V1` vía Issue etiquetado `lf-profile-resume-governed` → Actions/OIDC → Edge; el agente propietario invoca esas acciones automáticamente sin copiarlas al disparo.
- `lf_profile_native_bridge_prepare_v1` devuelve `NATIVE_MODEL_INPUT_READY` después del premodelo validado. El chat nativo produce RAW real y V3 conforme al contrato; `run_bound_validator` verifica Step50; `lf_profile_native_bridge_record_output_v1` registra 50/60 y `lf_profile_native_bridge_record_semantic_v1` + `lf_profile_native_bridge_record_report_v1` registran 70/80 dentro del mismo RUN. Sin atestación independiente inventada.
- Readback: `SELECT step_order,step_id,status,evidence_ref FROM public.lf_operation_execution_steps WHERE execution_id=:id ORDER BY step_order`, estado `COMPLETED` y `public.lf_profile_execution_terminal_authority_receipt_v1(:id)` = `READY`. Si el workflow tarda, reconsultar su run_id y el mismo `execution_id`; no relanzar BEGIN.

## SELECT readback del 13-nov-2026 (Supabase vivo, solo lectura)
- 11/11 pasos activos `EJECUCION_PERFIL_LF`, contratos `ACTIVE_ENFORCEMENT`; fuente BD real.
- **0** vínculos PERFIL→SKILL (`lf_activo_relaciones`), **4** relaciones PERFIL→`INPUT_GOVERNANCE_EXECUTION_CONTRACT` tipo `GOBERNADO_POR`; ese activo es `CONTRACT`, no `SKILL`.
- 8 registros del catálogo `lf_skill_catalog_v1`; **no** existe IG como entrada invocable allí. Algunos perfiles tienen metadatos heredados `input_governance_binding_mode=DIRECT_PROFILE`; no equivalen a `USA_SKILL`.
- El planificador devuelve `BLOCKED / PROFILE_LEGACY_DEPENDENCY_NOT_EXECUTABLE` si detecta esa dependencia sin skill ejecutable; **no** declara IG NOT_REQUIRED por ausencia de vínculo.
- Falta la vinculación real perfil–skill ejecutable, contrato de entradas/aplicabilidad y adaptador gobernado para IG. La resolución del plan sí está implementada como SQL candidato; **la invocación dinámica real en Step40 no queda acreditada ni activada** y la lógica heredada sigue en el runtime vigente. El PR NO-GO es intencional hasta integración verificada.

## Prueba aislada 0→80 · 2 casos, sin DML/DDL vivo
- `services/profile_runtime_api/tests/test_governed_profile_operation_bridge.py`: PostgreSQL 17.6 y 18.7, crea tablas de fixture con la secuencia obtenida por SELECT, instala la función candidata **dentro de transacción**, simula binding `IG_CONTEXT_PACK` y `OTRA_SKILL_FICTICIA` por separado; el mismo disparo mínimo no contiene nombre de skill, ni pasos.
- `SELECT public.lf_profile_execution_plan_v1(perfil_interno)` devuelve `READY`, 11 pasos ordenados con `next_if_pass` y un skill distinto por caso; ledger simulado 11/11 en ambos; verifica `BLOCKED` antes de normalizar vínculo heredado; `ROLLBACK_GENERIC_EMPTY=true`.
- Esto acredita **plan SQL genérico aislado**, NO invocación real del skill, modelo, ni cierre E2E; sin API/secretos, no se modifican RUN históricos ni Supabase vivo.
