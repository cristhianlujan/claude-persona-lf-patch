# LF Input Governance N-4 — Prueba Router → persistencia de run
Fecha: 2026-10-28 · PR #3269 · Rol: verificador de integración en lectura.

## Resultado

**12/12 PASS read-only**, usando el archivo SQL versionado exacto
`sandbox/lf_contract_gate_test/input_governance/ig_router_caller_run_persistence_readonly_regression_20261028.sql`
(blob Git `ff20445a343fc8a1a4b34b8e4e930fa6e65b704a`).
**Una solicitud NUEVA con escritura Router → IG todavía NO_VERIFICADA.**

## Lo que sí se ejecutó

- Entrada al Router ACT-0001 con el pedido literal histórico
  `Revisar login b2b para ver las reglas que le faltan`.
  `lf_router_pipeline_context_begin_v2` → `STAGE1_REQUIRED`,
  `transport_mode=CONTEXT_TRANSPORT`, `effect_authority=false`. **No creó run.**
- Stage 1 derivó `PRODUCTO`/negocio `LF`; mantuvo alcance PANTALLA
  **UNRESOLVED**, sin target ni perfil impuesto. `lf_router_pipeline_context_stage1_submit_v2`
  → `NEXT_TRANSITION_READY`, `profile_semantic_selection`,
  validación sin errores. La función no permite ejecución downstream.
- `lf_router_pipeline_context_profile_semantic_prepare_v2` →
  `PROFILE_SEMANTIC_SELECTION_REQUIRED`, 10 perfiles elegibles;
  no se simuló selección semántica ni aprobación de Gate 2.
- Se leyó evidencia persistida de una ejecución gobernada **anterior**:
  un consumidor `EJECUCION_PERFIL_LF/input_validate` referencia run IG
  `949`, pantalla 51, `CONTEXT_PACK`, mismo hash de fuente.
  En ese run: 47/47 familias PASS, 25/25 propuestas PASS, 6 chunks
  de Validator con total 47 familias, identidades Curator/Validator
  distintas, cero claves duplicadas y `COMPLETED_CURRENT`.
  El run 949 reemplaza 833 por linaje gobernado.
- Pruebas negativas en lectura del mismo ciclo de auditoría:
  `fn_input_governance_worker_spec_known_current_v1(51,'CONTEXT_PACK',949)`
  retornó `REUSE_CURRENT_RUN` dos veces con el mismo 949 y sin alterar
  recuentos. Run 948 retornó
  `INPUT_GOVERNANCE_KNOWN_CURRENT_RUN_BINDING_INVALID:948`;
  consumidor no permitido retornó
  `INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED`.
- Todas las consultas a Supabase usaron **solo lectura**; ningún
  `INSERT`, `UPDATE`, `DELETE`, migración, cambio de permisos,
  despliegue o llamada con service role fue ejecutado.

## Primer límite y ruta correcta para el ensayo nuevo

**NO_VERIFICADO: nuevo run real.**
`lf_router_pipeline_context_*_v2` opera en modo
`effect_authority=false`. No concede permiso para invocar el runtime
de escritura. El código revisado de
`supabase/functions/input-governance-agent-v1/index.ts`
requiere `SERVICE_ROLE_KEY`; Curator y Validator persisten por sus
RPC gobernadas. Esta sesión dispone de conector Supabase de solo lectura
y no dispone de ejecución autenticada de Edge. **No inyectar credenciales
ni llamar directamente las funciones internas.**

Próxima prueba real, por caller autorizado existente, no por SQL directo:
1. Mantener el contexto/selección del Router y completar Gate 2 por sus
   contratos reales. Un perfil/producto seleccionado **no** autoriza
   escrituras por sí solo.
2. Usar el handoff gobernado de consumo y la operación admitida;
   `input_validate` determina si IG requiere un run nuevo para
   la pantalla/consumidor permitido. No forzar nuevo run si sigue
   `NOOP` o `REUSE_CURRENT_RUN`: para probar creación real debe existir
   un cambio de fuente autorizado o pantalla elegible de test sin run.
3. El caller autorizado invoca Edge
   `input-governance-agent-v1` con `pantalla_id` y consumidor
   admitido, nunca con `target` o identidad autoproclamada.
   El agente materializa run en `input_readiness_runs`.
4. Continuar Validator mediante `run_id` retornado;
   aceptar `VALIDATOR_RESUME_REQUIRED` como continuación, no cierre.
   Verificar que el `run_id` no cambie, que las familias y propuestas
   se confirmen por claves únicas y que el consumidor conserve recibo.
5. Readback desde fuentes reales: conteo antes/después, identidad del
   run, assessments, proposals, timestamps y resultado, sin confundir
   aceptación técnica con permiso de publicar selectores o G4/G5.

**Criterio de salida:** solo un ensayo de escritura admitido y
readback de la ejecución **nueva**, sin duplicados, permitirá declarar
`PASS_ROUTER_TO_IG_NEW_RUN`. El 12/12 de la prueba actual es
`PASS_READONLY_ROUTER_AND_PERSISTED_CONSUMER`, no equivalente.

EKB consultado antes de operar:
`INPUT-GOV-CONSUMER-BINDING-001`,
`IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`,
`IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`,
`CI-MIGRATION-SOURCE-PARITY-001`.
No se duplicaron incidentes EKB ni se modificó el EKB vivo.
