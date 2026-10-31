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


## Lote 2 — contraste real e integración conservadora (2026-10-31)

### Perfil A: `product_director_lf`
- Fuente: `profiles/product_director_lf/SKILL.md`, blob Git `479ccb9261980100999935c8e84e32dac3adc160` leído desde `main`.
- Sección textual observada: `RUNTIME CRITICAL GATE — EXECUTE FIRST; OVERRIDES LATER FORMAT RULES`.
- Ítem dentro de esa sección: `0. AUTHORITY RESOLUTION FIRST.` (precede a 1–7).
- Contrato runtime en `contracts/runtime_binding.json` vincula schema/validator, **no publica catálogo formal de ID de pasos**.
- Resultado de lectura: paso textual ubicable; `CANONICAL_STEP_AUTHORITY_NOT_VERIFIED` para su uso como destino gobernado.

### Perfil B: `systemic_root_cause_repair_lf`
- Fuente: `profiles/systemic_root_cause_repair_lf/SKILL.md`, blob Git `39fe66baf7608eef5117edd5a5f40578c594a115` leído desde `main`.
- Sección textual observada: `Runtime method capsule`.
- Ítem: `4. Use the smallest search strategy that can falsify the hypothesis.` (cápsula 1–12).
- `manifest.json` y `contracts/runtime_binding.json` identifican pack/método y proyección; **no afirman que cada número de la cápsula sea un paso canónico de ejecución**.
- Resultado de lectura: paso textual ubicable; `CANONICAL_STEP_AUTHORITY_NOT_VERIFIED` para destino gobernado.

Estas dos lecturas **no demuestran** original → evolucionado: verifican diversidad de estructuras y anclaje textual de destinos. Los controles N1/N2 de diagnóstico no se deben reinterpretar como numeraciones universales.

### Código añadido al PR en modalidad solo lectura

- `skills/profile_creator/validators/operational_control_matrix_v1.py`: proyecta filas por `case_id:check_id` usando únicamente la medición existente de `operational_coverage_v1.measure`, sin re-evaluar checks ni alterar `EVOLUTION_DEMONSTRATED`.
- Resuelve una referencia de destino en `SKILL.md` por sección+ítem+título y hash SHA-256 del texto fuente. Ante ausencia, fuente desactualizada o ambigüedad, devuelve `DESTINO_PENDIENTE`. Un ancla textual válida devuelve `SOURCE_ANCHORED_NOT_CANONICAL`, no un PASS de autoridad.
- `sandbox/lf_contract_gate_test/profile_execution_runtime/test_profile_target_destination_matrix.py`: seis pruebas diseñadas para los dos perfiles, cambios/regresiones y fuente inexistente/desactualizada. **Ejecución automatizada de esas seis pruebas no verificada**.

### Integración siguiente en la ruta existente

1. El consumidor existente de Grupo 2 ejecuta `load_cases/load_runs/measure` sobre trusted root para ambos árboles. Solo **ese consumidor** pasa las mediciones a `build_control_matrix`; no aceptar resultados PASS declarados por el perfil.
2. El actualizador descubre el identificador canónico del paso **en cada perfil destino** (contrato, definición de ejecución o fuente de autoridad consultada), anexa ese recibo al binding y verifica su vigencia. Las anclas de Markdown son pistas, nunca autorización.
3. Agregar el reporte como evidencia complementaria de `regression_after` y `report_output` **después de resolver el contrato de consumidor**. No cambiar por este lote el comparador, el ledger, la política de Grupo 2 ni la ruta OIDC.
4. Validar tests nuevos en CI de ejecución real, incluir caso sin corrida, cambio de SHA, destino cruzado, regresión y rechazo a destino ambiguo. Solo después proponer enforcement en el consumidor.

**Estado del lote:** lectura real y código propuesto en draft; no se ha integrado al ejecutor ni ejecutado una prueba E2E con RAW de original y evolucionado. PASE SUCCESS del commit del PR no equivale a la ejecución de los seis tests nuevos.


## Lote 4 — Reporte complementario en pasos existentes (2026-10-31)

**Fuentes verificadas:** `public.lf_operation_step_contracts` leído en Supabase, operación `ACTUALIZACION_PERFIL_LF`, contratos `ACTIVE_ENFORCEMENT`: `regression_after` (orden 110) exige `before_after_matrix,adversarial_result,holdout_result`; `report_output` (orden 130) exige `result,exact_head,evidence_refs,open_blockers,next_gate`. El paso `deterministic_validation` (90) permanece intacto. Estos son números de **Updater**, no de pasos del perfil destino.

**Código incorporado en la rama draft:**
- `scripts/lf_profile_update_run.py` prepara una proyección acotada `LF_PROFILE_CONTROL_MATRIX_RECEIPT_V1` que incluye ID de caso/control, original/evolucionado, comparación, IDs de corridas, atestación, destino (o pendiente), resumen, hashes de árboles, hash SHA-256 del reporte, referencias `actions:profile-evolution-proof:<run_id>` y `approval_effect=NONE`.
- `regression_after.evidence_payload.before_after_matrix.control_matrix` adjunta **solo este recibo complementario**, sin sustituir `holdout_result` ni `before_after_matrix` preexistentes.
- `report_output.evidence_payload.control_matrix_report` adjunta el mismo recibo, sin alterar `result/exact_head/evidence_refs/open_blockers/next_gate`.
- Si la matriz supera el límite acotado de 16000 caracteres, el recibo declara `PARTIAL_ROWS_NOT_COMPLETE` y `row_count_omitted`. El reporte íntegro sigue en `<state>.matrix.json` local; **no** debe citarse esa ruta como evidencia accesible remotamente.
- La matriz no produce un PASS independiente; el resultado del comparador oficial y el juicio semántico conservan su propia autoridad. No hay SQL, Edge Function, cambio de contrato o mutación en Supabase.

**Pruebas y resultados de GitHub Actions sobre commit `78e1eb1a82d45c411a513926f5abdbc3d3901e04`:**
- Edge R17 `#41207860544`: SUCCESS, 115 pruebas del lane; su wrapper interno exige **14 pruebas** de la matriz.
- PASE `#41207860401`: SUCCESS.
- Se probaron compatibilidad con payload anterior, validación de transporte, enlace a corrida oficial, límite de tamaño, errores de schema y análisis del caso registrado WEB-001.

**Caso WEB-001:** se leen `WEB-001.case.json` (14 checks) y las dos corridas conservadas `RUN-WEB001-BASE-20261029.json` / `RUN-WEB001-CANDIDATE-20261029.json`. Ambos outputs tienen hash y árbol declarados; **ambos tienen `attestation=NONE`**. Esto prueba el readback del reporte usando registros existentes; no representa una ejecución actual, atestación de proveedor ni certificación semántica independiente.

**Hallazgo pendiente:** no se identificó catálogo de IDs canónicos de pasos de cada perfil en la inspección acotada de tablas con nombres de paso/perfil. Las anclas textuales se mantienen como `SOURCE_ANCHORED_NOT_CANONICAL` y los destinos sin referencia como `DESTINO_PENDIENTE`; no se inventan numeraciones.

**Cierre del lote:** implementación de reporte y pruebas CI completadas en PR Draft. No hay merge, despliegue, actualización de ledger real ni prueba E2E nueva ejecutada de original/evolucionado. El readback real de datos y los 14 tests son evidencia limitada, no certificación de evolución.
