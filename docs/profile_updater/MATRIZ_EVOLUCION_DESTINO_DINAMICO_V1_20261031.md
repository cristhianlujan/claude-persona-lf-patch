# LF — Matriz de evolución funcional y destino dinámico del perfil

**Estado:** propuesta de control / integración pendiente de revisión gobernada.
**Ámbito:** `ACTUALIZACION_PERFIL_LF`, perfil destino único por ejecución.
**Autoridad:** snapshot vigente en Supabase, estructura del perfil destino y contratos vinculantes. Este documento no crea pasos canónicos del Profile Updater ni sustituye Grupo 1, Grupo 2, juez, PASE o Merge Train.

## Propósito
Para cada control evaluado del caso operacional, comparar ORIGINAL vs EVOLUCIONADO, rastrear evidencia real y señalar **en qué paso del perfil destino** se conserva, agrega, modifica, sustituye o retira funcionalidad. La numeración del destino **no** es la de los pasos 70/80/90 del actualizador.

## Esquema de matriz por caso

| Campo | Obligación |
| --- | --- |
| `execution_id`, `profile_slug`, `case_id`, `case_input_sha256` | Identidad; mismo caso literal para ambas ejecuciones |
| `control_id`, `control_description`, `required` | Control tipado, derivado del contrato/caso, no inventado |
| `original_result`, `evolved_result` | `PASS/FAIL/NO_VERIFICADO/NO_APLICA`; este último solo con justificación |
| `original_raw_ref`, `evolved_raw_ref` | RAW real, hash del output y hash del árbol de cada perfil |
| `evidence_ref`, `verification_method`, `verified_at` | Evidencia localizable del verificador/ejecutor, nunca solo una afirmación del productor |
| `destination_profile_step_id`, `destination_profile_step_name` | Identidad exacta **del paso del perfil destino**, o `DESTINO_PENDIENTE` |
| `destination_source_ref`, `destination_source_sha` | Archivo/contrato/snapshot usado para resolver el destino |
| `change_type` | `CONSERVAR/MODIFICAR/AGREGAR/SUSTITUIR/RETIRAR` |
| `proposed_step_id`, `step_dependencies` | Solo si se propone un paso nuevo; propuesta ≠ paso incorporado |
| `regression_status`, `decision`, `blocking_code` | `PASS/FAIL/NO_VERIFICADO`; aceptación únicamente con prueba y gates completos |

## Ejemplo no factual

| Control | Original | Evolucionado | Destino en perfil | Cambio | Evidencia | Decisión |
| --- | --- | --- | --- | --- | --- | --- |
| Resolver responsable | FAIL | PASS | N1 (si existe realmente) | MODIFICAR | RAW y criterio ejecutado | PASS ilustrativo |
| Consultar reglas aplicables | FAIL | PASS | N2 (si existe realmente) | MODIFICAR | RAW y autoridad | PASS ilustrativo |
| Búsqueda semántica complementaria | FAIL | PASS | DESTINO_PENDIENTE | AGREGAR | RAW y evaluación | PENDIENTE de resolver destino |
| Preservar contrato | PASS | PASS | Paso existente por descubrir | CONSERVAR | Regresión | NO_VERIFICADO hasta mapear |

Los resultados anteriores **son ejemplos**, no prueba de que N1/N2 existan en cualquier perfil.

## Procedimiento obligatorio

1. Recuperar operación, EKB, contrato y snapshot vigente; identificar perfil exacto, versión, árbol y lista de pasos reales. No trasladar numeraciones entre perfiles.
2. Descubrir destinos en la fuente canónica y árbol vinculante. Preferir identificadores estables de paso; registrar nombre, archivo, versión, dependencias y evidencia de consulta.
3. Mapear cada control a paso existente, o proponer uno nuevo según las convenciones y dependencias **del perfil destino**. Nunca asignar `N2.1` u otra numeración por posición ni por analogía; ante ambigüedad: `DESTINO_PENDIENTE`.
4. Ejecutar **mismo caso literal** contra ORIGINAL y EVOLUCIONADO; conservar ambas salidas RAW, hashes de árboles y de outputs. Medir los controles bajo sus contratos, sin convertir `UNMEASURED` en PASS.
5. Comparar por control: `FAIL→PASS` = mejora demostrada; `PASS→PASS` = preservación; `PASS→FAIL` = regresión bloqueante; cualquier resultado sin evidencia = `NO_VERIFICADO`. `FAIL→FAIL` no es mejora.
6. Cuando hay fallo, vincular diagnóstico, cambio y destino; corregir candidato por ruta gobernada; repetir los controles afectados y regresiones. Si el candidato ya pasó github_write/github_readback, usar la enmienda gobernada solamente cuando PR #3412 esté integrado y operativo; no reescribir sus recibos.
7. Entregar matriz + referencias verificables en reporte y readback. Solo cerrar si Grupo 1, Grupo 2, evaluación semántica independiente, gates vigentes y ausencia de regresiones constan como aprobados.

## Reglas de decisión

- `DESTINO_PENDIENTE` o `NO_VERIFICADO` en un control material bloquea certificar la evolución hasta resolverlo.
- Un destino propuesto no es un paso implementado; debe materializarse y volver a descubrirse en el árbol del candidato.
- `RETIRAR` o `SUSTITUIR` requiere demostrar ausencia de pérdida de obligaciones/consumidores e impacto de dependencias.
- La matriz es **trazabilidad y reporte**, no sustituto de pruebas ejecutables ni autorización de escritura.
- Los identificadores `github_write`, `github_readback`, `deterministic_validation` pertenecen al **actualizador**, no son destinos del perfil objetivo.
- No cambiar política, esquema SQL, ledger, ruta Router ni código del verificador como consecuencia automática de este documento.

## Readback mínimo para el reporte
`execution_id | profile_slug | case_id | original_tree_sha | candidate_tree_sha | controles_total | mejorados | preservados | regresados | no_verificados | destinos_pendientes | Group1 | Group2 | semantic_review | PR/commit | dictamen | siguiente_accion`.

**Dictamen:** `APTO_PARA_GATES` solo con evidencia real, cero regresiones materiales, destinos resueltos y requisitos del snapshot; de otro modo `CORREGIR` o `BLOQUEADO_EVIDENCIA`. La integración y cierre son fases posteriores.
