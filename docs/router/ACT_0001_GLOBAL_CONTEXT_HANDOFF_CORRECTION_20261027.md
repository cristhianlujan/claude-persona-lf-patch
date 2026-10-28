# ACT-0001 — Corrección del contrato global de contexto y handoff

Estado: PROPUESTA DE CORRECCIÓN; SIN DESPLIEGUE. Origen: revisión directa de funciones desplegadas y migración 20261028020345_lf_router_pipeline_context_gate2_integration_v1.sql.

## Errores concretos detectados
1. La bifurcación `session_user='supabase_read_only_user'` en las funciones `lf_router_pipeline_begin_v1`, `lf_router_pipeline_stage1_submit_v1`, `lf_router_pipeline_profile_semantic_prepare_v1` y `lf_router_pipeline_profile_semantic_submit_v1` determina el modo de transporte por identidad técnica del llamador, no por contrato ni transición. Una solicitud funcional equivalente puede recorrer rutas diferentes por usar otro rol.
2. `LF_ROUTER_READ_ONLY_CONTEXT_V1`, `READ_ONLY_CONTEXT`, `ROCTX:` y los códigos `BLOCK_READ_ONLY_CONTEXT_*` codifican una restricción no deseada en un transporte que debe servir al pipeline global.
3. El parámetro `p_execution_id` recibe alternativamente un identificador persistente o un token JSON codificado. Esto mezcla identidad de ejecución con transporte de contexto, especialmente en prepare/submit.
4. El transporte termina en `READ_ONLY_GATE2_DERIVED_NOT_AUTHORIZED` y `GOVERNED_PROFILE_EXECUTION_REQUIRED`, mientras `lf_router_pipeline_profile_handoff_continue_v1` exige una ejecución `EJECUCION_ROUTER_LF` persistida con pasos sellados. No existe puente gobernado que materialice una ejecución del perfil desde el contexto validado, sin reiniciar el Router.
5. `trace_persistence='NONE'` comunica ausencia incondicional de trazabilidad cuando el contrato debe definir el momento y ámbito de persistencia.

## Contrato objetivo
- `LF_ROUTER_EXECUTION_CONTEXT_V2` (nueva versión; no reutilizar `V1` con otra semántica), `CONTEXT_TRANSPORT`, `RCTX2:` y `context_token`. Aceptar temporalmente el legado `ROCTX:` solo por un adaptador explícito de compatibilidad y validación.
- La selección de etapas, resoluciones y persistencia proviene del contrato de operación y de transiciones deterministas; nunca de `session_user` como selector funcional. La identidad del llamador sigue aplicándose a controles de autorización.
- Separar `execution_id` (identidad durable, solo al reservar ejecución gobernada) de `context_token` (datos transportados, sin autoridad intrínseca).
- Una derivación semántica o token provisto por el llamador NO es prueba de autorización. Antes del efecto o ejecución, validar texto original, SHA, versión, catálogo, selección semántica, Gate 2, estado de activo, ruta de operación y permisos; vincular el resultado a evidencia gobernada.
- Registrar ejecuciones solo donde el contrato lo requiera (admisión, operación, auditoría, efectos), sin escribir por cada transporte intermedio.
- El handoff debe reutilizar `lf_router_profile_execution_handoff_v1`, `lf_router_profile_execution_handoff_validate_v1`, `lf_router_profile_execution_after_gate2_v1`, `lf_profile_execution_begin_from_handoff_v1` y `lf_router_action_registry` según sus contratos; no llamar a materializadores con permisos de SQL solo lectura ni otorgar capacidad de escritura a esos roles.
- Conservar firma y comportamiento persistente existente durante la transición. Nuevas firmas de contexto explícitas, sin sobrecargar `p_execution_id`.

## Orden mínimo de implementación gobernada
1. Congelar contratos actuales y enumerar consumidores y roles de cada función.
2. Crear validador de contexto global V2 que verifique integridad, coherencia de etapas y revalidación en origen; distinguir autenticidad de contenido de autorización.
3. Exponer adaptador de entrada/continuación V2 basado en contexto y transición, con funciones de compatibilidad V1.
4. Implementar puente de admisión gobernada reutilizando `EJECUCION_PERFIL_LF`: valida evidencia, consulta acción `PERFIL/PROFILE_EXECUTION`, reserva ejecución real y retorna el handoff; prohibir ejecución con token no admitido.
5. Ejecutar regresión por la ruta canónica: `Stage1 → Stage2 → transición determinista → selección semántica → Gate2 → admisión → ejecución de perfil → retorno`; cubrir solicitudes de lectura, modificación, perfil no elegible, token alterado, operación no autorizada, reintentos y fallos.
6. Deprecar nombres antiguos solo después de demostrar ausencia de consumidores; no eliminar migraciones aplicadas.

## Bloqueo de seguridad
No es correcto sustituir globalmente `READ_ONLY_CONTEXT` por `CONTEXT_TRANSPORT` dentro de la migración ya aplicada ni quitar el guard `session_user` sin reemplazarlo por validación y permisos; ambas acciones permitirían interpretaciones o accesos inválidos. Las correcciones deben ir en una nueva migración por LF Migration Merge Train, con una sola migración por PR, tras completar el diseño ejecutable y los checks.

## Evidencia de referencia
- Migración aplicada: `supabase/migrations/20261028020345_lf_router_pipeline_context_gate2_integration_v1.sql`.
- `lf_router_action_registry`: `PERFIL/PROFILE_EXECUTION → EJECUCION_PERFIL_LF`, ACTIVE, write_allowed=false.
- El caso de Login B2B produjo `READ_ONLY_GATE2_DERIVED_NOT_AUTHORIZED` con `gate2_derivation.status='READY'` y `effect_authority=false`. No se autorizó ni ejecutó el perfil.
