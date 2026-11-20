# LF — simulación de 578 reglas y diseño de dos puertas, 2026-11-14

**Estado:** SOURCE-FIRST, SELECT REAL, NO PROMOCION. **Alcance:** solo sandbox. La V1 sigue instalada idéntica, incluidos los 262+8 históricos; no se cambian filas ni vínculo de pantalla.

## Decisión del owner implementada en V2

**Puerta VIGENTE (calidad + alcance con evidencia)**

`NO_PENDING_DECISION`, `NO_PENDING_MARKER`, `HAS_STATED_REASON`, `NO_DUPLICATE_ACTIVE_RULE` y `SCOPE_EVIDENCE`.

Orden de resolución del alcance:
1. >=5 pantallas ⇒ `FAST_5_PLUS`; no exige revisión *extra* de alcance.
2. 1–4 pantallas ⇒ `SCREEN_LINK`.
3. `es_transversal=true` + alcance explícito y no marcador sin resolver (`valor_config.scope/alcance/aplica_a/applies_to` o `scope_evidence_v2.declared_scope`) ⇒ `TRANSVERSAL_DECLARED`.
4. Backend: referencia explícita y comprobable a objeto REAL. Tablas (OID de PostgreSQL), funciones (catálogo pg_proc y nombre único), procesos (`lf_operation_contracts` con `contract_sha`), políticas (`lf_ops.politicas_seguridad.policy_code`). Se exige `scope_evidence_v2.evidence_ref` para las referencias estructuradas; se admiten `tabla_afectada/current_route_registry/runtime_source/canonical_table` legados cuando el objeto existe en catálogo. **Edge Function** sin registro canónico de despliegue verificable ⇒ `REVIEW_SCOPE`, no PASS ficticio.
5. Sin evidencia suficiente ⇒ `REVIEW_SCOPE` para Product Director o juez independiente, sin detener el resto del proceso. NO permite promoción automática.

En cualquier paso 0–80 los hallazgos de contenido se reportan y el flujo continúa, pero no se convierten en `PASS`. `independent_step70_required=true` en todos los casos. `identity_verified=false` B08 se conserva.

**Puerta POLÍTICA (amplitud diferente):** >=5 pantallas **o** `es_transversal=true`. V2 reporta `policy_breadth_pass` por separado; no aprueba una política ni cambia `lf_ops.pantallas_politicas_reglas`. PR [#3854](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3854) aún es DRAFT y trata políticas 19/22, no es un writer de regla→política ni habilita un bypass. La unión canónica existente pasa por `lf_ops.pantallas_politicas` y `lf_ops.pantallas_politicas_reglas` (13 vínculos de política, varios con una o más reglas).

## Resultado de simulación por SELECT

| Métrica | CANDIDATO | VIGENTE |
|---|---:|---:|
| Total | 166 | 412 |
| Con 5+ pantallas | 18 | 288 |
| Con 1–4 pantallas | 118 | 90 |
| Transversal declarada sin pantalla | 1 | 4 |
| Backend verificado sin pantalla | 1 | 1 |
| Alcance en revisión sin pantalla | 28 | 29 |
| Calidad aprobada + alcance directo | **64** | **324** |
| Calidad aprobada + revisión alcance | **7** | **11** |
| Otros fallos de calidad | **95** | **77** |
| Vía rápida 5+ y calidad | 0 | 284 |
| Puerta POLÍTICA por amplitud (sin otros requisitos) | 32 | 319 |

Causas de calidad (solapadas): CANDIDATO: decisión pendiente 57, marcador 66, razón ausente 3, duplicado 0. VIGENTE: decisión pendiente 57, marcador 57, razón ausente 9, duplicado 0. **335/412 VIGENTE** cumplen calidad, 324 con alcance directo y 11 a revisión. El hecho de que 77 VIGENTE históricos incumplan controles nuevos es hallazgo de consistencia, no una despromoción. No editar esos registros en este PR.

**Listado exacto:** [05_simulation_578_dual_gate_scope_v2_20261114.json](05_simulation_578_dual_gate_scope_v2_20261114.json). Incluye ID, código, estado, pantallas, ruta, causas por regla y SQL SELECT reproducible; listar allí las 77 VIGENTE que hoy no pasan calidad.

## Contrato de avance

`PASS`: cuatro criterios de calidad y alcance con evidencia directa; candidato puede seguir a Step70 real y aprobación, no queda automáticamente VIGENTE.

`REVIEW_SCOPE`: calidad correcta, sin evidencia de alcance; pasa a revisión Product Director/juez, no denegar RUN por contenido; no marcar promoción `PASS` hasta acreditar alcance.

`HOLD_CONTENT_FINDINGS`: falla calidad; registrar causas y continuar el proceso, pero no aplicar promoción.

Puerta política: `PASS_BREADTH` solo cuando la calidad también está correcta y amplitud cumple; `policy_breadth_pass` registra amplitud aislada sin confundir calidad.

**Pruebas requeridas:** PG17.6/18.7 con exacta migración versionada bajo BEGIN/ROLLBACK, backend real vs falso, una pantalla, transversal, pendiente owner, cinco pantallas fast, política, función/proceso/objeto, Edge sin registry, ACL service_role, V1 MD5 congelado y EKB 1→0 tras rollback. CI en HEAD exacto y Train gobernado; readback por SELECT. Nunca promover regla/política desde esta migración.

**Nota de riesgo:** esta primera versión hace verificación de existencia de objeto, **no** acredita que runtime implementa ese contrato. IG/Curator aporta fuente/alcance y prueba funcional adicional para producción. La clasificación SCOPE_REVIEW evita bloqueo de ejecución, pero deja promoción sin autorización automática.
