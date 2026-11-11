# Solicitud de ensayo end-to-end A1–A9 → PG-01 → PG-03 → PG-04 (2026-11-03)

**Estado:** `REQUEST_PROPOSED_ONLY / NOT_SUBMITTED_TO_RUNTIME / NO_AUTHORITY`. La petición no es un paquete A9 rellenado a mano, ni altera los snapshots ya persistidos.

## Solicitud del usuario al agente de Análisis

**Objetivo:** Obtener un paquete `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` candidato, actual y verificable para ensayar sin cambios en el producto la ruta de Programación hasta PG-04_C7, utilizando como caso de referencia un alcance **pequeño y aislado** de `B2B_APP_SHELL`.

> Analiza, sin implementar ni desplegar, una mejora acotada en el cascarón de interfaz `B2B_APP_SHELL`: identificar un elemento visual/funcional ya definido y autorizado cuyo comportamiento actual necesite un cambio mínimo y comprobable. **No inventes la existencia ni autoridad de ese cambio**. Primero localiza su definición vigente en EKB/producto y comprueba AS-IS del repositorio. Si la definición falta, difiere o requiere decisión, devuelve `REQUIRES_DECISION` o `NEED_MORE_EVIDENCE`, con referencias y la pregunta exacta. No elijas arbitrariamente `S01` como READY por haberlo sido en v0.9.
>
> Delimita al menos un outcome observable, sus requisitos y señales de aceptación, el componente afectado y los consumidores; conserva dependencias, errores, permisos, estado, efectos y persistencia incluso cuando resulten no aplicables (con evidencia). Ejecuta la secuencia A1–A9 siguiendo `ANALYSIS_PROCEDURE_V1`, sin decidir el HOW ni partir por archivos/tokens. Devuelve `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` más `PROGRAMMING_CONTEXT_SNAPSHOT_V1`, ambos `candidate_only` cuando corresponda, con los contratos tipados `IMPLEMENTABILITY_SCHEMA_V1`, `MATERIAL_FRONT_COVERAGE_V1`, `ANALYSIS_STOP_RULE_V1`, `scope_front_matrix`, `scope_readiness`, `source_refs`, `currentness_refs` y las huellas/recibos obtenidos solo por los mecanismos gobernados existentes.
>
> La calificación `READY` únicamente procede cuando las fuentes CURRENT, la matriz de frentes y las dependencias lo demuestran. Si un frente está bloqueado, mantenlo visible; un `STOP` de investigación no significa READY. No omitas obligaciones para lograr aceptación. No modifiques código, tablas, definiciones de producto ni autoridad.

## Selección y relación con los casos históricos

- **Objetivo candidato:** un único cambio en `B2B_APP_SHELL`, elegible **solo después** de que Análisis verifique su definición autorizada. Se pretende minimizar alcance para favorecer una ruta legítima de entrada.
- **Comparadores, no fuentes de autoridad:** `B2B_APP_SHELL v0.9` (`PARTIAL_READY`, 5/9 scopes antiguos READY) y `v1.0` (`NEED_MORE_EVIDENCE`, 0/9). No mutar ni reciclar sus `context_id` ni sus fingerprints.
- **Ruta de evaluación:** A1 alcance → A2 profundidad → A3 fuentes/authority/implementation actuales → A4 impacto real → A5 decisiones → A6 obligaciones tipadas → A7 cobertura → A8 STOP vs readiness → A9 paquete completo + persistencia/recibos con authority gobernada.
- **Condición para seguir:** PG-01 verifica `context_id` exacto, digests, currentness, matriz scope-frente, autoridad y recibo; PG-03 crea estrategia técnica candidata; PG-04 particiona por solución; C7 exige `SOURCE_SNAPSHOT VERIFIED` y revisor independiente.
- **Prohibido:** inventar evidencia de currentness, escribir SQL manual, marcar `PG-01_C6` DONE, construir un A9 sintético pasando por real, atribuir `INDEPENDENT_ASSURANCE` a un modelo sin proveedor/ledger, desactivar gates, cambiar `main` o promover un PR por PASS de pruebas locales.

## Cómo se interpretan los resultados

| Salida real de Análisis | Resultado correcto del ensayo |
|---|---|
| `READY_CANDIDATE` + A9 completo, fuentes y recibos auténticos | Probar admisión gobernada PG-01 (no automáticamente admitida). |
| `PARTIAL_READY_CANDIDATE` con scope independiente y limpio | Probar únicamente ese scope; jamás ocultar el resto. |
| `NEED_MORE_EVIDENCE` / `REQUIRES_DECISION` | Prueba de bloqueo correcta; documentar fuente o decisión pendiente. |
| `BLOCKED` | No seguir a Programación; no modificar el paquete para eludir el bloqueo. |

## Dependencia de infraestructura no resoluble solo editando el paquete

Según `profiles/programming_analysis_lf/README.md` (fuente actualmente en `main`), el perfil de Análisis figura `CANDIDATE_NOT_RELEASED / SOURCE_ONLY / OPERATIONAL_QUALIFICATION_BLOCKED`. Sus validadores `runtime_validate.py` y esquema `runtime_output.schema.json` pueden validar la forma de una propuesta, **pero no acreditan fuente, juez independiente ni PG-01**. El procedimiento A1–A9 en `ANALYSIS_PROCEDURE_V1.md` indica `PROCEDURE_SOURCE_COMPLETE / VALIDATION_DEFERRED` y prohíbe declarar READY sin evidencia.

**Por tanto:** la presente solicitud puede ejecutarse **como análisis candidato offline/documental**, pero para atravesar la ruta gobernada en vivo se necesita que el carril de Análisis habilite/atestigüe su ruta existente. No crear un motor paralelo ni autorizar llamada directa al perfil.

## Criterio de éxito

Éxito real del ejercicio no es «dar PASS a cualquier costo», sino determinar empíricamente: paquete completo con autoridad y recibos reales **o** primer bloqueo material real reproducible. Registrar por etapa los digests y evidencias. Mantener PR #3528 draft hasta calificación.
