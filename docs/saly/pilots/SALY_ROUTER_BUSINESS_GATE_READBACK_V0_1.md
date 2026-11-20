# SALY — readback de Router negocio y transición (lote 1)

**Fecha de verificación:** 2026-11-19 (hora local Perú).  
**Origen:** función PostgreSQL real en Supabase, con cuenta `supabase_read_only_user`.  
**Estado:** EVIDENCIA REAL de validación y bloqueo de negocio; **NO** es un RUN del perfil ni una ejecución end-to-end.

## Solicitud utilizada

`Para SALY, crear mockups y prototipos de pantallas utilizando el perfil UI y una skill de prueba Hola mundo.`

La salida Stage 1 fue **construida explícitamente para el piloto**, no es una evaluación de exactitud/consistencia de clasificación autónoma del modelo frente a un corpus. Incluye:
- `schema_version=LF_ROUTER_STAGE1_V2`;
- `negocio_codigo=SALY`, `canal_candidato=PRODUCTO`;
- `razon_seleccion` referida al texto de la solicitud;
- `downstream_execution_allowed=false`;
- `alcance.target_type=SCREEN`, `resolution_status=UNRESOLVED`.

## Lecturas reales

| Verificación | Resultado observado |
|---|---|
| `public.lf_router_business_catalog_v1` | `LF=ENABLED`, `SALY=RECOGNIZED_NOT_ENABLED` |
| `public.lf_router_stage1_validate_v2(stage1)` | `valid=true`, `codes=[]` |
| `public.lf_router_route_v1(stage1,{},false)` | `paso=NEGOCIO_NO_HABILITADO`, `negocio_codigo=SALY`, `canal_candidato=PRODUCTO`, `downstream_execution_allowed=false` |
| `public.lf_router_pipeline_context_begin_v2(literal)` | `status=STAGE1_REQUIRED`, `transport_mode=CONTEXT_TRANSPORT`, `next_step=stage1_seal`, `execution_id` ausente |
| `public.lf_router_pipeline_context_stage1_submit_v2(RCTX2 token,stage1)` | `status=NEXT_TRANSITION_READY`, `next_step=blocked_business`, `stage1_validation.valid=true` |
| `transition` | `transition_code=BUSINESS_NOT_ENABLED`, `transition_class=BLOCKED`, `effect_authority=false`, `caller_selects_next_step=false` |
| `profile_selection_request` | `jsonb_typeof(...)='null'`: **no hay shortlist ni solicitud de selección** |
| Handoff perfil | **NO ALCANZADO** |
| RUN UI Architect | **NO INICIADO** |
| Skill Hola mundo real | **NO INVOCADO** |

**Importante:** `NEXT_TRANSITION_READY` significa que se resolvió el **siguiente estado**; no significa que el Router aprobó pasar al perfil. El siguiente estado es precisamente `blocked_business`.

## Causa e implicación arquitectónica

1. El modelo nativo **propone** `negocio_codigo`; Stage1 V2 valida el contrato y comprueba que el código exista en el catálogo. El validador no es un clasificador semántico autónomo y no comprueba si la interpretación del modelo era la óptima.
2. El Router exige `lf_router_business_catalog_v1.status='ENABLED'` **antes** de crear un `profile_selection_request`. SALY existe, pero no está habilitado.
3. La responsabilidad de abrir y gestionar un RUN de `EJECUCION_PERFIL_LF` corresponde al perfil **después** del handoff admitido. El Router es de derivación y no debe abrir RUNs.
4. La política del UI actual contiene `INPUT_GOVERNANCE_CONTEXT_PACK` y `SCREEN_RULES_SNAPSHOT`; no existe binding vigente de `SALY_APP_VISUAL_PROBE`.
5. La selección semántica de perfiles no puede probarse sobre SALY hasta superar el gate; no se debe falsificar un `selected_profile_code` o un `profile_handoff` real.

## Siguiente lote propuesto: habilitación acotada, no global

- Diseñar una **excepción gobernada exclusivamente de derivación READ_ONLY** para el par `SALY + PRODUCTO` y un identificador de piloto explícito; **no** cambiar `SALY` a `ENABLED` globalmente, porque eso habilitaría rutas que no se evaluaron.
- Antes de implementar, revisar la fuente viva de `lf_router_route_v1`, la tabla de permisos/ámbitos y consumidores que comparten el Router (incluidos los invariantes LF). Comparar alternativas: binding de piloto con control por canal/operación frente a extensión de estado del catálogo. Escoger lo mínimo que no abra ejecución ni permisos de escritura.
- Probar solicitud SALY válida, SALY sin scope, negocio LF, negocio desconocido, multi-negocio y solicitud semánticamente ambigua. **Solo una vez obtenido handoff legítimo**, abrir RUN desde UI y evaluar skill selección.
- No hacer `UPDATE business_catalog.status='ENABLED'` como atajo. Cualquier implementación real requiere su PR, pruebas de regresión y autorización del impacto en Router.

## Estado de cierre

**Lote de diagnóstico: VERIFICADO.** Semántica de clasificación del modelo, habilitación de ámbito SALY, perfil, skill y RUN real siguen pendientes. `SALY_APP_VISUAL_PROBE` solo pasó pruebas offline en el PR candidato. Ningún registro de negocio fue modificado por estas lecturas.
