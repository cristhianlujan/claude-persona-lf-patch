# ADR-SALY-UI-001 — Autorización acotada de revisión del Design System

- **Estado:** DECISIÓN TÉCNICA CANDIDATA / `NO_GO` de activación
- **Fecha:** 2026-11-09
- **Solicitud:** [Issue #3714](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3714)
- **PR de evidencia:** #3715
- **Alcance:** solo `SALY_DS_V1`, perfil `PERFIL-UI-ARCHITECT`, revisión READ_ONLY
- **No cambia:** autorización global de SALY, ruta de LF, router único, arquitectura de ejecución de perfiles ni reglas financieras.

## Problema verificado

Existen cuatro guardas LF-only: `lf_router_route_v1` (business catalog), `lf_router_profile_after_selection_v1`, `lf_router_profile_execution_handoff_v1` y `lf_router_profile_execution_handoff_validate_v1`.

La operación `EJECUCION_PERFIL_LF` tiene un modo genérico read-only, **pero eso no constituye autoridad de negocio/artefacto**. La función nativa de perfiles requiere que el perfil reciba un contexto real de Gate2 y que GitHub OIDC/Edge autorice su BEGIN. Este mecanismo se debe reutilizar sin trasladar secretos al router.

## Decisión propuesta — perímetro en la arquitectura existente

**1. Fuente única y versionada:** reutilizar `public.lf_router_architecture_config_v1` para un objeto de control con clave `SALY_UI_REVIEW_V1` y estado inicial `DISABLED`. El valor declarado no es autorización hasta ser escrito/atestiguado mediante `ACTUALIZACION_ROUTER_LF`, con readback. No crear tabla, dispatcher, canal o runner nuevo.

**2. Alcance permitido inmutable por revisión:**

| Dimensión | Valor exacto |
|---|---|
| business | `SALY` |
| operation | `EJECUCION_PERFIL_LF` |
| channel | `PRODUCTO` |
| profile | `PERFIL-UI-ARCHITECT` |
| asset | `SALY_DS_V1` |
| asset_revision | `1.0.0-candidate.1` |
| action | `REVIEW_EXISTING` |
| effect | `READ_ONLY` |
| writes / promotion | `false` |

Vincular además el `request_sha256` literal, el SHA256 de `design_system.json` verificado desde GitHub y la revisión de política/operación. Un `target_hint` o `negocio_codigo` de Stage1 nunca constituye por sí solo autorización.

**3. Punto de autoridad:** hacer que los cuatro consumidores relevantes consulten una **misma decisión de ámbito exacto del servidor**; no copiar cuatro políticas divergentes. Si un helper SQL mínimo es necesario, ubicarlo dentro del módulo existente, sin nuevo sistema ni capa de routing. `SALY` permanece `RECOGNIZED_NOT_ENABLED`; la excepción permite **derivación de revisión**, no operaciones SALY.

**4. Fases fail-closed:**
- **Stage1/Stage2:** con política `DISABLED`, sin registro canónico o sin SHA exacto, `BUSINESS_NOT_ENABLED`. Con política `ACTIVE` y fuente exacta, solo continuar a selección semántica, nunca directamente al perfil.
- **Después de selección:** exigir `selected_profile_code=PERFIL-UI-ARCHITECT`, evidencia semántica vigente, el mismo `request_sha256`, solo lectura y `business=SALY`. Rechazar cualquier otro perfil/canal/operación.
- **Handoff y validador:** conservar la tupla exacta, fingerprint SHA256, revisión de operación, `effect_authority=false`, sin posibilidad de recalcular autoría desde los campos aportados por usuario.
- **BEGIN del perfil:** solo la ruta **existente** GitHub Issue → Actions OIDC verificado → Edge → RPC `service_role` interno. Edge debe confirmar también la vigencia de la autorización exacta y el binding al evento autenticado; sin ella, denegar. Nunca confiar en un `p_caller` JSON no autenticado.
- **Revocación:** desactivar la clave de configuración por vía gobernada; nuevos handoffs o BEGIN fallan cerrados. Una revocación no borra evidencia histórica.

**5. Salida:** revisión del perfil con `PRODUCTION_UI_SPEC`/dictamen compatible con su contrato V6, hallazgos P0/P1/P2, origen de datos y validadores. La revisión **no** activa el Design System.

## Matriz mínima de aceptación (12 casos)

| ID | Caso | Esperado |
|---|---|---|
| T01 | LF existente sin cambios | Misma ruta y autoridad |
| T02 | SALY sin autorización `ACTIVE` | `BUSINESS_NOT_ENABLED` |
| T03 | SALY exacto con autorización y fuente vigente | Selección semántica, no efecto |
| T04 | SALY con perfil diferente | `BLOCK` |
| T05 | SALY con activo diferente | `BLOCK` |
| T06 | SALY con acción, canal o modo distinto | `BLOCK` |
| T07 | `request_sha256` alterado / `target_hint` engañoso | `BLOCK` |
| T08 | Revisión de LF y SALY en un mismo pedido | `BLOCK` (autoridad separada) |
| T09 | Handoff falsificado, desactualizado o huella incorrecta | `BLOCK` |
| T10 | GitHub OIDC ausente/incorrecto | No iniciar ejecución |
| T11 | SALY solicita lectura de empleados, pagos o modificación | `BLOCK` |
| T12 | Revocación/rollback de permiso exacto | Regresa a `BUSINESS_NOT_ENABLED` |

## Dependencias y cierre

1. **Autoridad humana vigente** para registrar exactamente esa decisión en el sistema operacional; no basta este ADR.
2. Transporte de fuente **cumplido en PR #3715**: `candidate/design_system.json` Git blob `551469ed451f60af43e874c4688451a210a82dc1` (SHA256 original `2967f2e3cbdc6d4651ffd877a05fdd6c3377266561e522e22e315fe8e64096d5`), y `candidate/ESPECIFICACION_SALY_DS_V1.md` Git blob `12549166fe48450a405d62d4bbed58bb694a1ec9`. La captura aprobada permanece fuera de GitHub y sigue siendo dependencia para cotejo visual exacto.
3. Evidencia de que la ruta existente de Edge/OIDC puede comprobar la tupla sin ampliaciones de acceso.
4. Parche incremental reversible mediante `ACTUALIZACION_ROUTER_LF`; para migraciones, solo `ACTUALIZACION_DB_LF` y Merge Train, conforme a AGENTS.md.
5. Pruebas T01-T12 sobre HEAD congelado, readback contra DB y ejecución real con identificador nuevo.

**Al día de hoy: SOLAMENTE PROPUESTA.** `SALY` no está habilitado, `SALY_DS_V1` no está registrado como activo y `UI Architect` no ha ejecutado la revisión por el router.
