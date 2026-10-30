# Handoff: systemic_root_cause_repair_lf — búsqueda por niveles, cierre "exploré todo" y triaje

Fecha: 2026-10-29. Estado: CANDIDATO local, NO publicado en `profiles/**`. Este PR es borrador y solo trae el parche y esta nota.

## Qué contiene
`SRCR_CATALOG_CASCADE_CANDIDATE_20261029.patch` (aplica con `patch -p1` dentro de `profiles/systemic_root_cause_repair_lf`). Toca 6 archivos:
- `SKILL.md`: (a) triaje al inicio (actualizar perfil -> devolver al Router con `ACTUALIZACION_PERFIL_LF` por `GOVERNED_PROFILE_UPDATE_DISPATCH_V1`; ejecutar perfil -> `EJECUCION_PERFIL_LF`; incidente -> sigue el método); (b) paso 2 de la cascada con búsqueda por niveles N1..N6; (c) texto de cierre "exploré todo lo alcanzable y no encontré evidencia".
- `validators/producer_depth.py`: una cascada con las 5 clases cubiertas ya no se rechaza; exige `cascade.search_record` (clase, fuente, ubicación, resultado). Declarar una clase `NO_SOURCE_ACCESSIBLE` exige `cascade.catalog_checked` con entradas N1, N2, N3 y N4.
- `validators/terminality_gate_v1.py`: sub-estado `evidence_state` = `EXPLORED_NO_EVIDENCE_FOUND` | `SEARCH_INCOMPLETE`. El valor de `status` NO cambia (sigue `NEEDS_MORE_EVIDENCE`).
- `evals/v05_*`, `evals/v08_*` ajustados; `evals/v09_exhausted_search_cases.py` nuevo.

## Niveles de búsqueda (todos verificados: existen y responden con SELECT)
- N1 vistas listas: `v_lf_fuente_operativa_busqueda` (223), `v_lf_inventario_activo` (223), `v_lf_operation_contract` (65), `v_lf_operation_policy_snapshot` (166), `v_lf_operation_steps_with_contracts` (682), `v_lf_github_reconciliation_queue_v3` (64, todas STALE), `v_lf_deuda_abierta` (40), `v_lf_healthcheck` (1), `v_lf_artifact_destination_registry` (4).
- N2 tablas canónicas: `lf_activos`, `lf_operation_contracts`, `lf_operation_step_contracts`, `lf_operation_judges`, `lf_operation_execution`, `lf_decisiones_gov`, `lf_error_knowledge`, `lf_backlog_errores_operativos`, `lf_deuda_documental`, `lf_patches`, `lf_eventos`.
- N3 resto de la base por descripción (`pg_description`: 63/116 tablas y 41/97 vistas la tienen).
- N4 GitHub (árbol de `main`, luego ramas/PRs). N5 documentos de proyecto y memoria. N6 cierre.
- No legible con el acceso RO: `v_lf_artifact_inventory_status_v3` (permiso denegado sobre `fn_lf_artifact_v3_evidence_valid`).

## Pruebas (reglas, no modelo)
v05 33/33, v08 13/13, v09 7/7, v07r1 terminalidad 10/10. `v07r1_runtime_context_budget_cases.py` ya falla en main (preexistente).

## Corridas con modelo (caso WEB-001, a ciegas, 1 corrida por versión; el caso varía entre corridas)
- exam8: no validó (cascada agotada sin salida válida).
- exam9: validó, NEEDS_MORE_EVIDENCE con registro de las 5 clases; no usó el catálogo (marcó fuentes `NONE`).
- exam10: no validó (17 errores; no armó el andamiaje completo de NEEDS_MORE_EVIDENCE).
- exam11 (con niveles): validó, SYSTEMIC_REPAIR_SPEC; saltó N1 y N5 y ningún validador lo detectó.

## Pendiente (en este orden)
1. Exigir al menos una consulta N1 y una N2 en todo cierre con búsqueda registrada, no solo cuando se declara una clase sin fuente (hoy el orden no se verifica). Con su prueba.
2. Repetir la corrida varias veces por árbol: el mismo perfil dio 9/9 y 6/9, una sola corrida no sirve de evidencia.
3. Decisión abierta: el estado sigue llamándose `NEEDS_MORE_EVIDENCE`. Cambiar el nombre tocaría migraciones y validadores.
4. Para pasar a `profiles/**`: solo por `ACTUALIZACION_PERFIL_LF` (`scripts/lf_profile_update_run.py`); antes hace falta un run operacional candidato ligado al nuevo `profile_tree_sha256` mergeado a main por el Train. No hay nada de eso hecho.
5. Cuando estén aprobadas, lo ideal es que N1/N2 salgan de una vista única en la base (migración por el Train, nombre `lf_...`); hoy están escritos en el SKILL.md.
6. Pendientes ajenos: 2 ramas remotas sin borrar (`lf/profile-op-case-product-director-hmo-pricing`, `lf/profile-op-case-ci-parity-001`), caso `CI-PARITY-001` sin correr, alias SUPER_ADMIN, 7 checks semánticos.

## No se hizo
Nada escrito en la base, nada en `profiles/**`, sin changeset manifest (borrador, sin label `ready-to-merge`).

## Addendum de auditoría N1/N2 con datos (2026-10-30)

**Alcance candidato, NO aplicado a `profiles/**`.** El parche adjunta la ampliación T4b del juez semántico independiente EXISTENTE. No introduce otro agente/juez ni migración.

- Para cada dato material, el juez debe recibir o leer resultados reales N1/N2 con fuente, consulta, fecha, filas, identificadores y valores relevantes, digest/referencia y vínculo al manifest externo.
- `N1_N2_AUDIT_V1` es la estructura de observación del juez, NO una nueva tabla ni autoridad. El juez repite una lectura acotada cuando tenga acceso. El manifiesto externo sigue siendo la fuente comprobable; texto del productor no sustituye readback.
- Diferenciar `ROWS`, `EMPTY`, `ACCESS_DENIED`, `ERROR`; contrastar valores N1/N2, conservar divergencias y separar cada dato con su ID.
- No permitir PASS cuando no hay consulta real o no puede recuperarse el resultado; una falsa afirmación de ausencia devuelve al trabajador o bloquea si hay evidencia fabricada.
- **Pendiente de implementación aparte del texto del juez:** cablear suministro real de observaciones verificables N1/N2 al contexto de ejecución y los validadores deterministas, y ejecutar pruebas negativas/operacionales ligadas al hash exacto del nuevo árbol. Esta modificación de instrucciones NO prueba que ya estén cableados.
- No cambiar `NEEDS_MORE_EVIDENCE`; no activar runtime ni publicar.

## Lote: validación determinista de readback N1/N2 (2026-10-30)

**Cambio implementado en el parche candidato (no en `profiles/**`):**

1. `validators/producer_depth.py`: cada incertidumbre `DESIGN_BLOCKING` con búsqueda exhaustiva requiere `cascade.catalog_queries[]` con registros N1 y N2 distintos, referidos al mismo `uncertainty_id`, cada uno con `evidence_id` único.
2. Cada `catalog_queries[].readback` debe contener `source`, `query`, `result_kind`, `row_count`, `sample_records` con valores tipados, `observed_at` y `snapshot`. El validador exige `ROWS` o `EMPTY` coherentes (no acepta denegación como ausencia), consulta de lectura y coincidencia exacta de `source_locator` y SHA-256 canónico del readback con una entrada `CURRENT` del manifiesto externo.
3. `validators/terminality_gate_v1.py`: `EXPLORED_NO_EVIDENCE_FOUND` solo cuando cada material abierto tiene un `datum` único y sus cinco clases están completas con resultado `NO_EVIDENCE` o `NO_SOURCE_ACCESSIBLE`. Duplicación de dato, evidencia hallada u omisiones dan `SEARCH_INCOMPLETE`. El estado público sigue siendo `NEEDS_MORE_EVIDENCE`.
4. `judges/systemic_root_cause_semantic_judge.md` añade T4b: muestra las filas/valores, confronta N1 contra N2, reconsulta una fuente de forma acotada, comprueba ausencia real y detecta contradicciones; no acepta una declaración de consulta como prueba.
5. `evals/v09_exhausted_search_cases.py`: además de los siete casos iniciales, incorpora cuatro escenarios falsos de terminalidad y ocho casos de recibos N1/N2 (valores inventados, identidad errónea, duplicación, ausencia declarada, manifiesto faltante y consulta no SELECT).

**Evidencia disponible:** simulación de aplicación de todos los fragmentos del parche sobre el contenido leído de `main`: 16/16 fragmentos localizados y consistentes, sin conflictos de contexto. Prueba aislada previa del algoritmo de recibos: 7/7; no sustituye ejecución de la suite del candidato. Referencia del PR en borrador: #3359.

**No certificado:** ejecución Python completa del árbol candidato, comparación operacional WEB-001 sobre `profile_tree_sha256` nuevo, invocación y salida efectiva del juez semántico, resultado `N1_N2_AUDIT_V1` exigido por el flujo, y transporte real desde el resolver que materializa el manifiesto de evidencia. En particular, el manifiesto V1 solo contiene referencia y digest de cada evidencia, no las filas: el readback debe llegar como dato independiente y estar vinculado al digest del manifiesto. Sin esa prueba, NO se puede declarar pase semántico o perfil actualizado.

**Siguiente lote:** aplicar el parche en árbol temporal limpio, ejecutar suites incluyendo v09, probar el transporte externo de N1/N2 y conectar el dictamen T4b al validador del resultado semántico antes de realizar corridas modeladas. Mantener `profiles/**` intacto y no añadir `ready-to-merge`.

## Lote siguiente: quality-boundary N1/N2 + prueba aislada (2026-10-30)

**Código preparado exclusivamente en el archivo .patch del PR #3359:**

- `validators/validate_semantic_judge_result.py`: agrega validación del resultado `n1_n2_audit` contra el candidato exacto, por `uncertainty_id + level` y por `evidence_id`, `source_locator`, SHA-256 del `readback`, `row_count`, `result_kind` y `sample_records`. Un `n1_n2_verdict != PASS` impide `PASS_INDEPENDENT_SEMANTIC`. Los N1/N2 ausentes se detectan a partir del caso, sin confiar en la declaración de aplicabilidad del productor.
- `validators/validate_quality_receipt.py` y `validators/materialize_quality_receipt.py`: suministran el candidato real y el manifiesto externo al validador semántico en ambos puntos de aceptación. El resultado del juez ya no puede hacer PASS final con omisiones N1/N2 cuando el dato pendiente lo exige.
- `judges/systemic_root_cause_semantic_judge.md`: formaliza los campos obligatorios del resultado independiente. El juez debe hacer una lectura real de control; `independent_source_ref` por sí solo no prueba que haya sido ejecutada.
- `validators/producer_depth.py`: N1/N2 usan `source_kind=VIEW|BASE_TABLE` para evitar inferir el tipo por el prefijo del nombre. Fuente/consulta/filas deben estar referidas a evidencia externa CURRENT.
- `evals/v10_n1_n2_quality_gate_cases.py` (nuevo): 10 pruebas reproducibles incluidas en el candidato. Ajustado el caso v05 que antes parecía aceptar búsquedas exhaustivas sin readback N1/N2.

**Evidencias independientes de este lote:**
1. Readback read-only en Supabase: `v_lf_fuente_operativa_busqueda` es `pg_class.relkind=v`; `lf_activos` es `relkind=r`. Ambas fuentes devuelven un registro para `PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF`, con `estado_documental=CANDIDATO` y `estado_operativo=READ_ONLY` (consultas independientes).
2. Prueba Python local, aislada del repositorio y sin DB: **12/12 PASS** (incluye falta N2, digest equivocado, valor alterado, dato cruzado, evidencia SUPERSEDED y FAIL semántico); material experimental solo, sin equivalencia a ejecución oficial.
3. Verificación sintáctica estructural del parche respecto de las fuentes de GitHub en commit `173088b756d79839bb1cb7b4ba63ee53bad389bc`: **22/22 hunks con contenido y tamaños de contexto correctos**, 11 destinos, 1 test file nuevo. NO es `git apply` real ni compilación Python del árbol completo.
4. GitHub: el PR sigue DRAFT, sin tocar `profiles/**`, sin efectos en producción/Supabase ni label ready-to-merge.

**Bloqueos de cierre operacional (NO_VERIFICADO):** 
- No se ejecutó Python del árbol candidato completo ni el archivo nuevo v10 en un checkout del repositorio; la sesión local no tiene acceso de red a GitHub. No reclamar v10 PASS.
- No hay evidencia todavía de invocación real del juez con resultados N1/N2 y un readback independiente de fuente durante la evaluación; una referencia redactada por el juez no es un recibo verificable de ejecución. Falta el proveedor/transportador de resultados hacia el límite de calidad.
- No se realizó WEB-001 ligado al árbol candidato ni comparación evolutiva por hash, ni Router/Updater/Train, ni merge.

**Dictamen:** candidato mejorado y chequeado en forma aislada; calidad oficial/actualización operativa **NO_VERIFICADO**. No modificar perfil canónico, ni marcar PASS operacional, ni cerrar el PR por esta evidencia. Siguiente lote limitado: ejecución del test v10 y las suites existentes en checkout gobernado, readback del judge real y bloqueo de PASS adversarial, luego caso WEB-001.

## Lote verificable: comprobante independiente N1/N2 (2026-10-30)

### Hallazgo reproducido
Se reprodujo mediante Python aislado, con transcripción de la lógica candidata anterior, que `independent_source_ref` no vacío podía ser inventado y aun así producir un dictamen válido. **No era correcto afirmar que la revisión independiente había ocurrido.**

### Reparación candidata dentro del PR #3359
- La auditoría semántica exige un cuarto input `quality_readback` distinto del candidato, manifiesto y respuesta del juez, suministrado por el ejecutor de calidad. No se recibe desde texto del reparador.
- `quality_readback` liga `candidate_sha256` y `manifest_digest` calculados, identifica N1/N2 por `datum_id`, y presenta `receipt_ref`, `execution_id`, `source_locator`, `observed_at`, `result_kind`, `row_count` y `sample_records`.
- El validador rechaza referencia inventada del juez, comprobante ausente, valor divergente, hash de manifiesto erróneo, candidato ajeno y falta de nivel.
- Ambos puntos de aceptación, `materialize_quality_receipt.py` y `validate_quality_receipt.py`, pasan el argumento independiente al validador de resultado semántico. Su default `None` preserva compatibilidad histórica, pero el caso V0.6 con N1/N2 material requiere el comprobante; sin ello falla cerrado.
- El archivo `evals/v10_n1_n2_quality_gate_cases.py` contiene **14 aserciones sintéticas** con casos adversariales de recibos de calidad. Se corrigió una línea con prefijo extra que impedía ejecutar el script.

### Evidencia
- **15/15 pruebas de Python aisladas PASS** con reconstrucción explícita de la lógica del guard y readbacks sintéticos. Incluye reproducción del falso positivo antes de corregirlo y rechazo posterior de referencia inventada.
- **25/25 fragmentos del parche** reconstruidos y contrastados por contenido/tamaño/contexto con los archivos de GitHub en commit `173088b756d79839bb1cb7b4ba63ee53bad389bc`. 11 destinos de archivo; no es comprobación `git apply` sobre checkout completo.
- Readback N1/N2 en Supabase ya corroborado para el perfil: vista `v_lf_fuente_operativa_busqueda` y tabla `lf_activos`, tipo físico respectivo `v`/`r`, mismos valores materiales y una fila en cada fuente.
- GitHub head del parche tras reparación: `c2908787781a4797ce5de3d01157bcf3d67e7231` (PR todavía DRAFT).

### Evidencia faltante / cierre
**NO_VERIFICADO:** corrida Python exacta de las suites v05/v08/v09/v10 sobre checkout limpio; readback realmente producido por el runtime independiente y no por un paquete de prueba, validación del recibo de calidad en el flujo activo, ejecución operacional WEB-001 con hash nuevo, comparación evolutiva, Router/Updater/Train y eventual merge.

El nombre `QUALITY_BOUNDARY` dentro de un JSON NO autentica por sí mismo al emisor. El conector/ejecutor de calidad debe suministrar este bundle fuera del canal del productor, registrando recibos de lecturas efectivas. Hasta acreditar ese transporte independiente, cualquier PASS N1/N2 real debe permanecer BLOQUEADO/NO_VERIFICADO. No prometer que la existencia de la firma del método ya equivale a cableado del ejecutor.

## Readback en runtime vivo: evidencia y dependencia exacta (2026-10-30)

Se inspeccionó directamente Supabase, sin escribir:

- `public.lf_profile_execution_trust_validation_v2(text,text,jsonb)` **existe**; el cuerpo vigente NO contiene la cadena `quality_readback` (posición 0). Su control de `semantic_judge` compara pasos predecesores, autoridad, candidate/scope digest, `model_call_count`, `validator_status` y `semantic_judge_result`, pero no vincula un recibo independiente de valores N1/N2.
- `public.lf_profile_execution_canonical_read_judge_v1(text)` **existe**, pero su salida determinista y condiciones de autorización son propias de `READ_PRODUCT_DEFINITION` con `LF_PRODUCT_CANONICAL_RULE_READ_V1`. NO es un verificador genérico N1/N2 para `systemic_root_cause_repair_lf`; reutilizarlo sin una evaluación gobernada mezclaría contratos.
- En el candidato, el argumento Python `quality_readback` es un contrato de transporte propuesto, no una prueba de que el ejecutor lo provea. Un `issuer='QUALITY_BOUNDARY'` escrito por el propio productor tampoco demuestra procedencia; requiere receipt de paso/operación producido fuera del modelo y readback de consulta real.
- **Dependencia:** preparar un cambio ACOTADO y gobernado del consumidor de calidad del `EJECUCION_PERFIL_LF` para transportar y atestar resultados N1/N2 exclusivos de casos SRCR aplicables; mantener sin cambio el `READ_PRODUCT_DEFINITION` canónico ni afectar otros perfiles. No hay autorización implícita para migrar ni desplegar producción desde este handoff.
- Hasta tal implementación y verificación en el runtime, `N1_N2_AUDIT_V1` operativo, el judge independiente y WEB-001 permanecen NO_VERIFICADO y el PR sigue DRAFT.

No se debe abrir una prueba operativa de calidad como PASS sobre datos sintéticos. La prueba Python aislada (15/15) confirma únicamente lógica de rechazo, no invocación gobernada del juez.

## CORRECCIÓN DE ALCANCE — misma secuencia con enforcement existente (2026-10-30)

**Este apartado reemplaza expresamente las propuestas anteriores que hablaban de un transportador `quality_readback`, un emisor `QUALITY_BOUNDARY` o un nuevo consumidor de calidad. No deben implementarse.** Se conserva la trazabilidad de esas propuestas como diseños descartados, no como requisitos pendientes.

### Readback del proceso vigente en Supabase

Se consultaron directamente las tablas `public.lf_operation_step_contracts` y `public.lf_operation_step_judge_bindings` para `EJECUCION_PERFIL_LF`.

| Paso existente | Orden | Estado enforcement | Condición / enlace |
|---|---:|---|---|
| `research_baseline_freeze` | 47 | `ACTIVE_ENFORCEMENT` | `research_baseline_binding`, `baseline_receipt_ref`, baseline inmutable |
| `execute_profile` | 50 | `ACTIVE_ENFORCEMENT` | `research_baseline_digest`, `research_baseline_ref`, `profile_output`, `source_refs` |
| `output_validate` | 60 | `ACTIVE_ENFORCEMENT` | `output_contract_result`, `deterministic_validation` |
| `semantic_judge` | 70 | `ACTIVE_ENFORCEMENT` | `semantic_judge_result`, `unsupported_claims` |
| `report_output` | 80 | `ACTIVE_ENFORCEMENT` | prev. juez PASS; `result`, `profile_code`, `execution_id`, `no_write_performed` |

`public.lf_profile_execution_trust_validation_v2(text,text,jsonb)` **ya compara** predecessor clean de `input_validate` / `execute_profile`, scope/candidate digest, independencia del juez y limpia salida de `semantic_judge`; `report_output` exige paso 70 PASS con hashes coincidentes. **No comprueba hoy el contenido material N1/N2** ni el vínculo de un readback independiente a su fuente real.

### Enlace correcto, sin proceso nuevo

**Única ruta:** `EJECUCION_PERFIL_LF` -> `research_baseline_freeze` -> `execute_profile` -> `output_validate` -> `semantic_judge` -> `report_output`. Los pasos 47, 50, 60, 70 y 80 son los existentes. No añadir pasos, wrappers autónomos, segundo juez, tablas ni autoridades nuevas.

- El reparador entrega los datos materiales, consultas y referencias de sus fuentes mediante los campos y evidencias existentes de `execute_profile`.
- El **mismo juez semántico** del paso 70 lee el candidato y referencias, hace su lectura N1/N2 y emite `n1_n2_audit` / `n1_n2_verdict` **dentro de `semantic_judge_result`** con evidencia de consulta y vínculo a los recibos anteriores.
- Los validadores deterministas verifican estructura, IDs de cada dato, fuente, filas, tipos, resultados y digest contra el manifiesto. La **autenticidad del readback y el orden** deben ser comprobados por el **enforcement existente del paso 70**, contrastando los recibos externos de ejecución y su autoridad, no una cadena textual autoemitida por el juez.
- Si el enforcement existente carece de uno de esos controles, **solo extender `lf_profile_execution_trust_validation_v2`/el contrato ya vigente del paso 70 por la ruta gobernada**. No invocar otro proceso ni ejecutar SQL directo. FAIL / falta de readback confiable / discrepancia -> no se registra PASS en el paso 70 -> no se llega a `report_output`.
- `lf_profile_execution_canonical_read_judge_v1` está restringido a `READ_PRODUCT_DEFINITION`; no reutilizarlo como juez N1/N2 genérico por similitud de nombre.

### Cambio concreto de este lote

- Parche candidato del PR #3359: se **eliminaron por completo** los argumentos y verificaciones del transporte paralelo `quality_readback`, las nuevas firmas de materialización/quality receipt y los cuatro casos asociados del v10. Se mantiene validación de integridad N1/N2 en el juez existente, sin cambiar el contrato público de quality receipt.
- Ampliación del juez actual documenta el enlace obligado al paso 70 y su enforcement vigente.
- **22/22 fragmentos de parche** aplican por simulación sobre los contenidos de GitHub en `173088b756d79839bb1cb7b4ba63ee53bad389bc`, 11 destinos. La prueba v10 se redujo a **10 casos propuestos**, aún NO ejecutados sobre el árbol real. El 15/15 reportado antes fue evidencia de **otra versión descartada** y no se aplica al candidato actual.

### Estado verificable

`PR #3359`: DRAFT, solo documentación/candidato; sin editar `profiles/**`, sin desplegar ni modificar Supabase. **Requiere** evidencia de activación del enlace N1/N2 bajo el enforcement vigente y corrida WEB-001 sobre el árbol resultante; no hay pase ni cierre oficial.

## CHECKPOINT ENFORCEMENT VIGENTE — SIN FLUJO NUEVO (2026-10-30)

### Evidencia leída de Supabase (solo lectura)
- El activo PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF declara research_baseline_mode=NOT_REQUIRED y runtime_enabled=false. Un readback reciente de research_baseline_freeze trae mode=NOT_REQUIRED, baseline_digest=NOT_APPLICABLE y baseline_snapshot={}. El paso se ejecuta pero no aporta datos N1/N2.
- EJECUCION_PERFIL_LF: research_baseline_freeze (47) -> execute_profile (50) -> output_validate (60) -> semantic_judge (70) -> report_output (80). Todos los contratos y jueces tienen ACTIVE_ENFORCEMENT; report_output depende del PASS semántico anterior.
- ACTUALIZACION_PERFIL_LF: github_write (70) -> github_readback (80) -> deterministic_validation (90) -> semantic_judge (100) -> regression_after (110) -> post_merge_reconcile (115) -> close (120). Todos ACTIVE_ENFORCEMENT: esta es la ruta de actualización del perfil, no el paso 70 del runtime.
- El trust validator público lf_profile_execution_trust_validation_v2(text,text,jsonb) compara predecesores, candidate/scope digests, identidad independiente y dictamen pero no comprueba todavía filas/valores N1/N2.
- Los registros recientes con independent=false y PASS_SELF_REVIEW_NOT_INDEPENDENT de este perfil pertenecen a ACTUALIZACION_PERFIL_LF, NO a EJECUCION_PERFIL_LF. No mezclar recibos ni asumir equivalencia de pasos homónimos.
- Un registro de EJECUCION_PERFIL_LF de 2026-09-22 está BLOCKED en semantic_judge con INDEPENDENT_SEMANTIC_JUDGE_EXECUTOR_NOT_WIRED; evidencia histórica no extrapolable como estado actual sin nueva prueba. Los source_refs de otra ejecución reciente de execute_profile contienen GitHub/contexto, no readback N1/N2.

### Único enlace autorizado (propuesta candidata, no aplicada)
1. Actualizar el perfil por ACTUALIZACION_PERFIL_LF (incluyendo su propio semantic_judge 100). No editar profiles/** directamente ni abrir proceso adicional.
2. Cuando se ejecute el perfil, aportar las consultas y recibos N1/N2 por el contexto y source_refs ya disponibles en EJECUCION_PERFIL_LF. El MISMO semantic_judge 70 consulta read-only y devuelve n1_n2_audit y n1_n2_verdict dentro del semantic_judge_result existente.
3. El enforcement EXISTENTE del paso 70, lf_profile_execution_trust_validation_v2, debe comprobar: mismo execution_id y hashes de candidato/scope; fuentes N1/N2 relevantes, observación real, datum_id, campos tipados, filas, digests y readback independiente; discrepancias y acceso denegado no son ausencia. Si el enforcement carece de estos controles, ampliar esta misma llamada por su ruta gobernada, sin nueva tabla, paso, servicio ni wrapper.
4. Baseline NOT_REQUIRED no se emplea como evidencia de consultas. Un source_ref autodeclarado no demuestra relectura; de no poder comprobar procedencia, NO PASS.
5. report_output 80 ya tiene enlace de enforcement con semantic_judge 70: sin PASS del 70, se bloquea 80. Preservar estado NEEDS_MORE_EVIDENCE cuando corresponda y no hacer cierre prematuro.

### Matriz de verificación futura
| Escenario | Esperado |
|---|---|
| N1/N2 reales, relevantes, coherentes e independientemente comprobados | PASS solo tras otros controles |
| Solo N1 o N2 sin ausencia justificada | FAIL/RETURN |
| Se declara EMPTY, pero fuente real devuelve fila | FAIL |
| Valor, datum_id o hash no coinciden | FAIL |
| Referencia de consulta independiente inventada | FAIL |
| Baseline NOT_REQUIRED utilizado como supuesta prueba N1/N2 | FAIL |
| Intentar report_output tras FAIL del juez | BLOCKED en paso ya existente |
| Otros perfiles sin aplicabilidad N1/N2 | Sin regresión |

Estado: solo parche candidato en PR #3359. Suite completa y WEB-001 por hash nuevo NO_VERIFICADO; runtime sin enforcement específico N1/N2 y perfil runtime_enabled=false. No aplicar cambios a función de producción desde este handoff.

## ALCANCE DE ADOPCIÓN POR PERFIL — UBICACIÓN DINÁMICA, NO PASO UNIVERSAL (2026-10-30)

**Regla del usuario:** el Profile Updater incorpora/evoluciona una capacidad o paso; **cada perfil adoptante debe ubicarla en el lugar que exige su propia naturaleza, contrato y secuencia**. El hecho de que el perfil reparador tenga un juez en paso 70 NO establece ese número, ese tipo de paso ni esa estructura para otro perfil. Esta precisión prevalece sobre cualquier instrucción anterior que pudiera interpretarse como imposición universal.

### Evidencia viva de gobernanza (solo lectura)
- `ACTUALIZACION_PERFIL_LF.method_selection` (35) tiene `ACTIVE_ENFORCEMENT`, resolver `public.lf_profile_update_evolution_step_guard_v1` y exige selección de métodos calificados con identificador, versión y recibo.
- `ACTUALIZACION_PERFIL_LF.evolution_decision` (37) tiene `ACTIVE_ENFORCEMENT` y decide `NO_CHANGE` o `UPDATE`, modos vigentes `PATCH`, `SPECIALIZE`, `ADAPT`, `REARCHITECT`, `OPTIMIZE`.
- La definición vigente del guard `lf_profile_update_evolution_step_guard_v1(text,text,jsonb)` **NO comprueba el `step_id` de instalación, el orden ni los enlaces predecessor/successor del perfil adoptante**. Es una brecha de evidencia, no una capacidad ya implementada.
- El flujo existente continúa por `change_scope` (40) y `regression_plan` (50), más validaciones y readbacks gobernados. La decisión de ubicación debe quedar explícita y verificable allí; si sus actuales contratos/jueces no la comprueban, se amplían esos controles dentro de la gobernanza existente, sin crear un proceso paralelo.

### Contrato de decisión por perfil (campos de evaluación; no se introduce esquema ni tabla nueva)
| Campo a verificar | Fuente / regla |
|---|---|
| Perfil y revisión AS-IS | Resolver el perfil canónico y su `source_head_sha` exacto |
| Capacidad seleccionada | `selected_methods`, `method_id`, `exact_version`, recibo de calificación |
| Naturaleza y objetivo | Defecto/uso y alcance de evolución decidido en el perfil |
| Paso receptor | `step_id` y operación obtenidos del contrato/ruta actuales del perfil, **sin asumir número fijo** |
| Acciones | Adicionar, adaptar, sustituir o retirar comportamiento según su encaje, sin duplicar pasos |
| Secuencia | Predecesor, sucesor, entradas, salidas, `next_if_pass` / `next_if_blocked` / enforcement aplicables |
| Evidencia | Datos y recibos reales, vínculo a ejecución, hash exacto y readback posterior |
| Regresión | Caso positivo y negativo de ese perfil; no alterar otros perfiles o caminos |

**Ejemplo acotado:** para SRCR, la comprobación N1/N2 de calidad se ubica en su juez operacional existente (`EJECUCION_PERFIL_LF.semantic_judge`, 70). Otro perfil podría ubicar investigación N1/N2 antes de elaborar su resultado o durante validación; se determina leyendo su contrato antes del cambio. El juez del actualizador (`ACTUALIZACION_PERFIL_LF.semantic_judge`, 100) supervisa la evolución, NO impone la ubicación al perfil.

### Enforcements mínimos para admitir adopción
1. La selección de método calificado **no equivale** a autorización de instalación en cualquier paso.
2. Si existe un paso compatible, enlazar al paso mediante el contrato/call y su enforcement vigente. No crear otro juez/etapa por defecto.
3. Si se requiere un paso verdaderamente nuevo, hacer evolucionar **ese perfil** por el mismo `ACTUALIZACION_PERFIL_LF`, indicando su inserción y las dependencias con enforcement, no cambiando globalmente todos los perfiles.
4. Sin readback del paso receptor, predecesor/sucesor y ejecución/regresiones correctas: `NO_VERIFICADO` o bloqueo. No cerrar como PASS ni promover.

**Pruebas a agregar en el proceso actual:** adoptar en un perfil cuyo paso receptor sea distinto de SRCR; rechazar step_id inventado, inserción fuera de orden, cambio sin llamada enforzada y reutilización de recibos entre perfiles; aceptar cuando el perfil no requiere la capacidad (NO_CHANGE). Todo sujeto a corrida gobernada; **NO probado aún**.

**Estado:** se ajustó la instrucción candidata de SRCR y este handoff en el PR #3359, todavía DRAFT y sin modificaciones oficiales a perfiles/runtime. El guard de colocación por perfil requiere implementación y prueba mediante los controles vigentes; no se reporta como resuelto.

## CHECKPOINT — NATIVE STEP PLACEMENT GUARD (CANDIDATO, NO INSTALADO) (2026-10-30)

### Ejecución del lote
- Se añadió a **este mismo PR #3359** el módulo candidato `docs/profile_updater/handoffs/PROFILE_NATIVE_STEP_PLACEMENT_VALIDATOR_CANDIDATE_20261030.py` y el archivo de pruebas `docs/profile_updater/handoffs/test_profile_native_placement_candidate_20261030.py`; ambos permanecen **fuera de `profiles/**` y fuera de las migraciones activas**.
- Es **un validador puro para ser llamado por el Profile Updater vigente**, NO un nuevo workflow, proceso, operación, etapa, perfil, autoridad ni motor de métodos.
- Contrasta el perfil y revisión de origen, grafo nativo AS-IS de pasos, IDs y orden únicos, predecesores/sucesores, método seleccionado, tipo de modificación `INSERT|MODIFY|REPLACE|REMOVE`, punto receptor y enlace de enforcement.
- El segundo control compara el grafo de la revisión candidata contra la revisión base: inserción/remoción/reemplazo realmente materializados; llamada y enforcement presentes; sólo se alteran pasos previstos y enlaces de vecinos. La renumeración ordinal sin alteración material se permite.
- Prueba aislada local con un espejo equivalente de la lógica: **21/21 PASS**, incluidos dos perfiles con ubicaciones diferentes, source head obsoleto, identidades cruzadas, falsos enlaces, método no seleccionado, cambio lateral al enforcement de vecino, llamadas omitidas y no-realización. Los archivos exactos de GitHub no se ejecutaron como checkout; **no elevar ese resultado a suite oficial**.

### Enlace que DEBE ejecutarse mediante el proceso existente
| Punto actual | Llamada prevista | Evidencia obligatoria |
|---|---|---|
| `ACTUALIZACION_PERFIL_LF.method_selection` (35) | Mantener el selector y calificación vigentes, sin colocar un paso por defecto | `selected_methods`, `source_head_sha`, recibo de calificación y evaluación existente |
| `evolution_decision` (37) | Mantener decisión `UPDATE|NO_CHANGE`, sin presumir instalación | Decisión y AS-IS exacto |
| **`change_scope` (40)** | Llamar a `validate_change_scope_placement` cuando el alcance incluya adopción de método/paso | Mapa de pasos **obtenido por el lector confiable GitHub exact-ref existente** (no enviado por productor), método seleccionado, acción, paso receptor y vecinos |
| **`regression_plan` (50)** | Requerir positivos, negativos, adversariales y aislamiento de pasos para la ubicación concreta | Referencia/digest del placement admitido en 40; pruebas antes de escritura, mismas referencias del perfil |
| `github_write` / `github_readback` (70/80) | Conservar escritura/readback ya gobernados, sin rutas alternativas | Commit, blobs leídos y `exact_head` del propio perfil |
| **`deterministic_validation` (90)** | Llamar a `verify_candidate_placement_readback` contra mapas exactos antes/después | Call/enforcement real del paso cambiado, enlaces adyacentes, hashes base/candidato y no regresión |
| `semantic_judge` (100), `regression_after` (110) | Revisar semántica y falsificación según el contrato existente | Evidencia independiente y casos operacionales |

**Dependencia física NO RESUELTA:** el guard vivo `lf_profile_update_evolution_step_guard_v1` se invoca solo en pasos 35 y 37. El guard vivo `lf_profile_update_substantive_block_v1` se invoca desde el recorder para los demás pasos, pero hoy **no llama al validador de ubicación**. No basta con alojar el .py en docs: el caller/recorder nativo debe recibir un mapa de pasos del perfil con procedencia comprobable, y ejecutar los checks dentro de los pasos 40 y 90 existentes. Si un perfil expresa la secuencia solo en texto libre y no hay grafo estructurado/recibo fiable, detener la admisión, NO inventar IDs, ni copiar el paso 70 del reparador.

**Condición de no regresión:** no reinterpretar metodologías usadas únicamente para investigar como adopciones persistentes; aplicar el placement obligatorio solo cuando `change_scope` determine incorporación/reemplazo/eliminación de un paso o capacidad del perfil. Verificar esa determinación contra el diff real en el readback posterior (la declaración del productor no es autoridad). Mantener `NO_CHANGE` legítimo sin exigir una inserción falsa.

### Estado y siguiente lote
- Candidato y tests registrados en el mismo PR. GitHub conserva PR DRAFT, sin escribir `profiles/**`, sin migraciones ni cambios de Supabase.
- **NO_VERIFICADO:** ejecución del archivo exacto de GitHub en runner, extracción autenticada y normalización del grafo de pasos del perfil desde GitHub actual, llamada física en `change_scope`/`deterministic_validation`, bloqueo real por el recorder y casos de regresión transversal.
- Siguiente lote: determinar el mínimo readback de grafo admitido por el caller nativo `run-creacion-perfil-lf` sin inventar otra fuente, y preparar **el cambio en los puntos actuales de llamada/enforcement** por `ACTUALIZACION_PERFIL_LF` antes de proponer su pase al train. Si no existe dato confiable, mantener bloqueado.

## Lote adicional — readback de método y ubicación nativa (2026-10-30)

**Verificación de ruta activa (solo lectura):** `supabase/functions/run-creacion-perfil-lf/index.ts` ya tiene `GITHUB_PUBLIC_API_EXACT_REF_V1` para revisión exacta y `GITHUB_ACTIONS_EVOLUTION_PROOF_V1` para medir/comparar. No se necesita otro proceso. Pero el caller todavía NO entrega un mapa nativo autenticado de pasos internos a `change_scope`.
El recorder vivo `lf_record_profile_operation_step_v1` invoca el guard de evolución para `method_selection` (35) / `evolution_decision` (37), y para los demás checkpoints invoca `lf_profile_update_substantive_block_v1`. La ubicación de nuevas capacidades deberá controlarse dentro de `change_scope` (40), `regression_plan` (50), readback de GitHub y `deterministic_validation` (90), manteniendo esos pasos, sus destinos y su enforcement.

**Evidencia de perfiles distintos:** en GitHub `product_director_lf` usa `Mandatory decision trajectory`, `customer_financial_ux_decisioning` usa `Workflow / route`, y `systemic_root_cause_repair_lf` usa `Gap-resolution cascade`. Sus estructuras son diferentes; no imponer el orden 70 a todos ni inferir IDs de pasos únicamente de encabezados Markdown.

**Código candidato adicional (NO integrado):**
- `docs/profile_updater/handoffs/PROFILE_NATIVE_STEP_PLACEMENT_VALIDATOR_CANDIDATE_20261030.py`: funciones puras para comprobar `source_head_sha`, identidad del perfil, fuente, grafo nativo, IDs, adyacencias, métodos, acciones `INSERT|MODIFY|REPLACE|REMOVE`, contenido SHA256 por paso, enlaces de enforcement y diff candidato. Un renumerado ordinal legítimo no es regresión; cambios imprevistos en contenido/call/enforcement de vecinos sí lo son.
- `docs/profile_updater/handoffs/test_profile_native_placement_candidate_20261030.py`: 22 casos definidos; una ejecución aislada de un **espejo equivalente local** pasó **22/22 PASS**. No afirmar que es ejecución del archivo exacto en GitHub, ni un readback operacional real.

**Conexión obligatoria DENTRO del updater vigente (PENDIENTE):**
1. En `change_scope` (40) el caller obtiene el grafo nativo exacto de GitHub por el lector ya existente (no del usuario/modelo), verifica la adopción específica y ejecuta el candidato. Si no hay fuente estructurada para ese perfil, resultado `NO_VERIFICADO/BLOCKED` para la adopción; nunca inventar el paso.
2. En `regression_plan` (50), atar casos positivos, negativos y adversariales al mismo perfil/head y a la ubicación de paso realmente elegida.
3. En `github_readback` (80) / `deterministic_validation` (90), releer la revisión escrita y comprobar llamada, enforcement, enlaces y ausencia de cambios fuera del alcance antes del PASS. Preservar la comprobación de GitHub Actions `compare` y recibos de misma ejecución.
4. El juez del UPDATER en paso 100 revisa el sentido de la ubicación. Cada perfil adopta la capacidad en su propio paso operativo, no en el paso 100 ni universalmente en el 70.
5. `NO_CHANGE`: si no se instala ningún método o paso, no crear ficticiamente una ubicación; preservar el flujo condicional vigente.

**Bloqueos verificados:** no existe aún la provisión autenticada de un mapa de pasos nativos para todos los perfiles; el caller y recorder actuales NO invocan ese validador en 40/90; falta test físico de enforcement y perfiles cruzados. Tener el script en `docs/` no lo instala, ni emite autoridad, ni permite merge. PR #3359 DRAFT sin cambios oficiales en `profiles/**`, Supabase, runtime o Edge. WEB-001 sigue sin pase operacional.
**Siguiente checkpoint:** proyectar el grafo nativo con fuente/hash verificables a partir del exact-ref existente; luego enlazar a llamadas ya gobernadas de 40/90 y probar bajo el mismo updater, sin otra ruta.

## CHECKPOINT — ENLACE EXACT-REF AL CALLER ACTUAL (CANDIDATO 2026-10-30)

### Alcance ejecutado — no se cambió ningún proceso ni perfil oficial
- Se preparó el parche `docs/profile_updater/handoffs/PROFILE_NATIVE_CALLER_WIRING_CANDIDATE_20261030.patch`: modificaciones previstas en el Edge caller **existente** `supabase/functions/run-creacion-perfil-lf/index.ts` y su helper en el mismo directorio Edge. No se cambió el código fuente vivo ni se desplegó Edge.
- El mismo caller obtiene los `selected_methods` desde el `method_selection` ya registrado y las `native_step_adoptions` del `change_scope` (40). No acepta un grafo enviado por el productor como fuente autorizada.
- `verified_native_placement_readback_candidate_20261030.ts` usa el lector `githubJson` existente para recuperar archivos exactos de `profiles/<slug>` desde el commit congelado. Valida perfil/ruta, encabezados ancla reales, orden, adyacencia, fuente, blob SHA, SHA256 de la sección y acciones INSERT/MODIFY/REPLACE/REMOVE. Sin adopción declarada, compara los encabezados del SKILL.md antes/después para bloquear nuevas etapas ocultas.
- En `deterministic_validation` (90) lee el recibo previo de `change_scope` de la **misma ejecución**, el hash base y commit del `github_write` y vuelve a consultar GitHub por exact-ref. El cambio se inscribe en el recibo normal del paso. No hay segundo pipeline ni autoridad externa.
- La inicialización existente del updater agrega un flag **congelado para ejecuciones nuevas** `native_placement_gate_version=PROFILE_NATIVE_PLACEMENT_SOURCE_READBACK_V1`, evitando reinterpretar corridas históricas.
- Se creó el borrador `docs/profile_updater/handoffs/PROFILE_NATIVE_PLACEMENT_SUBSTANTIVE_GUARD_CANDIDATE_20261030.sql`: copia derivada del cuerpo vivo de `lf_profile_update_substantive_block_v1`, ampliando el **mismo guard** sobre 40 y 90; verifica array de adopciones, proveedor/caller, mismo perfil/commit, cobertura, predecesor y resultado fuente. **No es una migración aplicada** ni prueba de enforcement operacional. Debe materializarse bajo gobernanza; no editar migraciones históricas.
- Se añadió `verified_native_placement_readback_candidate_20261030.test.ts` con 10 casos negativos/positivos de la lectura GitHub exact-ref. **Definidos, todavía no ejecutados** en Node/Edge del repositorio.

### Readback y verificación propios
- Se releyó `run-creacion-perfil-lf/index.ts` desde GitHub; el diff candidato de 4 hunks se aplicó por **simulación de contextos y longitud: 4/4 PASS**, incluyendo nueva fuente helper fiel al archivo candidato. No es `git apply --check` de un checkout ni deployment.
- Se leyó con commit fijo `173088b756d79839bb1cb7b4ba63ee53bad389bc` el `SKILL.md` de `product_director_lf` y `customer_financial_ux_decisioning`: ambos contienen pares de encabezados distintos, únicos y adyacentes. Es prueba de anclas documentales reales, **no** de la validez semántica del paso ni de un enforcement físico. Sin cambios a esos perfiles.
- El test local Python aislado de 22/22 (lote anterior) permanece válido para su validador candidato; no debe presentarse como ejecución del nuevo helper TypeScript ni del SQL.

### Riesgo de pase — BLOQUEADO, no cierre prematuro
1. El helper de GitHub certifica **fuente**, no que una llamada de enforcement al paso nuevo realmente se ejecutó. El estado fuente es `SOURCE_ONLY_NOT_ENFORCEMENT`; jamás equipararlo a habilitación operacional.
2. No existe en todos los perfiles un mapa canónico de pasos/contratos ejecutables. Los encabezados Markdown son anclas de revisión, NO autoridad para inventar `step_id`; si no hay mapeo/autorización específica, retornar NO_VERIFICADO/BLOCKED y pasar al mismo updater para su decisión de evolución.
3. El archivo SQL candidato requiere materialización del guard actual con preflight/readback por ruta gobernada; la función activa de Supabase sigue intacta. El Edge caller también sigue intacto.
4. Antes de permitir PASS final a una adopción nueva, conectar un comprobante auténtico del **enforcement de ese paso y de su secuencia** en el `regression_after`/juez existente, sin inventar paso ni runner. Fuente conocida y hash correcto son condiciones necesarias, no suficientes.
5. Prueba mínima siguiente: ejecutar los 10 casos TypeScript desde la misma revisión, comprobar dos rechazos adversariales 40/90 por el recorder tras desplegar el cambio gobernado, y verificar NO_CHANGE / un perfil distinto sin regresión. No reabrir baterías interminables.

**Estado:** el PR #3359 sigue DRAFT y solo modifica archivos `docs/profile_updater/handoffs/**` (8 archivos en revisión). Cambios candidatos preparados; instalación, SQL materializado, enforcement real y corridas operacionales **NO_VERIFICADO**. Próxima ruta: ACT-0001 -> ACTUALIZACION_PERFIL_LF -> readback/test/semantic_judge/regression_after -> merge train según sus contratos actuales.

## Lote 2026-10-30 — prueba del lector, Router y enforcement de pase

### Ejecución y evidencia (separar herramientas reales de simulaciones)
- El validador local de ubicación (Python aislado, copia/equivalente del código candidato) corrió 22 pruebas: **22 PASS / 0 FAIL**. No equivale a corrida de checkout GitHub.
- Se leyó el fuente exacto `verified_native_placement_readback_candidate_20261030.ts` del PR y se ejecutó su lógica en un sandbox JS con tipos TypeScript retirados y mocks de `atob`, `TextDecoder`, `TextEncoder` y digest de `crypto.subtle`. **12/12 checks de comportamiento PASS**; la prueba de SHA256 criptográfico real y la compilación/ejecución nativa TypeScript no fueron verificadas.
- Las 12 comprobaciones incluyeron inserción válida, cambio declarado, eliminación, método no seleccionado, ancla inexistente, ruta entre perfiles, referencia base/candidato idéntica, inserción no declarada, orden no adyacente y NO_CHANGE. Se observó que el helper permite modificar contenido interior de una sección sin adopción declarada si no hay cambio de títulos: **eso no certifica no-adopción**; el juez semántico debe contrastar alcance y diff. Evitar sobreprometer detección automática exhaustiva.
- Read-only Router ACT-0001, sin pistas de target/action: pedido sobre `systemic_root_cause_repair_lf` y PR #3359 devolvió `BLOCKED / BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED`, sujeto candidato `PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF`, `next_governance_entrypoint=GOVERNED_SEMANTIC_CONSUMER_REQUIRED`, `downstream_execution_allowed=false`, request SHA256 `79da51c4f05247a5d7efb41d05047e9420bbdc47fc8a6120723d7fd2ac81e4cf`. Este BLOCKED no se interpreta como decisión terminal, pero la herramienta actual es Supabase **solo lectura** y no emite ni consume el recibo semántico gobernado para realizar la admisión. No fabricar recibos ni abrir otra ruta.
- El ledger `private.lf_evidence_ledger_v1` contiene **44** `GRAPH_RECEIPT` `VERIFIED` exclusivamente de `subject_type=IG_SCREEN_GRAPH`, `gate_code=IG_GRAPH_SHA_RECEIPT`. Son de Input Governance y no pueden usarse como prueba del mapa de pasos de perfiles. No hay un recibo de tipo PROFILE_STEP_GRAPH verificado identificado en esa población.
- GitHub Actions sobre commit `2925fb78c034a22dab5d86f89613171fd57f0cc2`: PASE workflow run **41076137909 SUCCESS**; su job `PASE / MIGRATION_SOURCE_PARITY` quedó **SKIPPED**. Esta señal demuestra aceptación de la presentación documental del PR, **no** activación del Edge, materialización SQL, juicio independiente ni regression_after de perfil.

### Correcciones al candidato
- `PROFILE_NATIVE_PLACEMENT_SUBSTANTIVE_GUARD_CANDIDATE_20261030.sql` amplió el mismo guard en sus pasos **semantic_judge** y **regression_after**, solamente para ejecuciones nuevas marcadas con `native_placement_gate_version=PROFILE_NATIVE_PLACEMENT_SOURCE_READBACK_V1`, exigiendo resultado semántico independiente PASS y adversarial/holdout PASS cuando existe adopción real. No se crean etapas ni se cambian corridas históricas.
- El guard de fuente no prueba una llamada ejecutable a cada método. Hasta contar con evidencia independiente de ejecución por el proceso/caller vigente, el pase semántico no puede declararse certificado aun con una prueba source-first y PASE verde.

### Primer error operacional y siguiente paso vigente
| Control | Resultado |
|---|---|
| PR solo docs, GitHub PASE | PASS (no equivale al perfil operativo) |
| Control determinista aislado Python/JS | 22/22 y 12/12 PASS, con límites indicados |
| Router ACT-0001 | BLOCKED por intención de mutación sin atestación semántica |
| Consumer semántico gobernado | NO EJECUTADO: no hay herramienta de emisión/consumo autorizada en la sesión |
| Fuente exact-ref / ejecución independiente | CANDIDATO; no instalado ni probada la llamada real |
| Materialización y regresiones del guard SQL | NO_VERIFICADO, sin mutación SQL |
| WEB-001 con revisión del perfil | NO_VERIFICADO |

**Siguiente paso de la secuencia existente (NO inventar otro):** consumir el handoff semántico en el `GOVERNED_SEMANTIC_CONSUMER_REQUIRED` de ACT-0001 mediante el actor/caller con autoridad, admitir a `ACTUALIZACION_PERFIL_LF` y recién entonces ejecutar el mismo train (40, 50, 70, 80, 90, 100, 110). Mientras no exista ese recibo/autoridad, mantener PR #3359 DRAFT; no modificar `profiles/**`, Supabase ni Edge vivo directamente. El cierre operacional sigue BLOQUEADO, con primer error reproducible identificado.

## Rectificación 2026-10-30 — continuar desde ejecuciones existentes

**Prevalece sobre todas las referencias anteriores del handoff a 'ruta nueva', 'volver a admitir Router ACT-0001', 'crear otra ejecución de actualización' o repetir las pruebas existentes.** La consulta a `lf_router_resolve_v1` con un texto nuevo en el lote previo produjo BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED solo porque se **planteó una solicitud de actualización nueva**. Ese bloqueo no es el estado del proceso histórico del reparador ni debe convertirse en requisito para retomar lo ya ejecutado.

### Readback de Supabase de la operación existente
| Ejecución vigente/histórica | Estado | Pasos | Evolución | Juez independiente |
|---|---|---|---|---|
| `EXEC-ACTUALIZACION-PERFIL-LF-OIDC-b62a195e-d912-4abd-a30e-0e4be5efe1e3` (2026-10-29) | COMPLETED | 17/17 `STEP_PASS_WITH_EVIDENCE` | `EVOLUTION_DEMONSTRATED` | `independent=false` |
| `EXEC-ACTUALIZACION-PERFIL-LF-OIDC-6862980c-d902-41d7-8c43-2b0de0114350` (2026-10-29) | COMPLETED | 17/17 `STEP_PASS_WITH_EVIDENCE` | `EVOLUTION_DEMONSTRATED` | `independent=false` |
| `EXEC-ACTUALIZACION-PERFIL-LF-OIDC-818f0acd-a1a2-47e2-9e5c-0eaeb5aef4ab` (2026-10-29) | COMPLETED | 17/17 `STEP_PASS_WITH_EVIDENCE` | `EVOLUTION_DEMONSTRATED` | `independent=false` |

**Evidencia de la primera ejecución:** `method_selection` S26 15/15 y déficit operativo WEB-001; `change_scope`, `regression_plan`, `pre_write_execution_binding_gate`, `github_write`, `github_readback`, `deterministic_validation`, `semantic_judge`, `regression_after`, `post_merge_reconcile`, `close`, `report_output` ya registrados PASS. `deterministic_validation` aporta WEB-001 de 4/9 base a 9/9 candidato, sin checks regresados, `EVOLUTION_DEMONSTRATED`. La operación completó y registró un merge anterior; esta evidencia NO prueba incorporación del **nuevo parche de ubicación dinámica del PR #3359**, que continúa solo en docs y DRAFT.

### Decisión de continuidad — sin ruta ni batería nueva
1. No iniciar otro Router, no volver a ejecutar 17 pasos, ni repetir S26/WEB-001 por el solo hecho de revisar el PR en borrador.
2. Reutilizar los recibos exactos de las tres ejecuciones como baseline histórico (step readback y hashes) y diferenciar claramente el nuevo candidato del trabajo ya integrado.
3. Si el perfil adoptante requiere una capacidad nueva, usar el MISMO Profile Updater, sus decisiones 35/37 y su colocación individual según contrato; sin paso 70 universal y sin proceso de colocación paralelo. Solo correr delta/casos realmente nuevos al momento de su impacto gobernado.
4. Mantener una dependencia diferenciada, no una repetición de pruebas: en la ejecución completada `independent=false`, y el reporte conserva siete verificaciones semánticas WEB-001, holdout y otros asuntos como siguientes gates no realizados. No borrar ni convertir estos avisos en PASS.
5. Ninguna escritura de código fuente oficial, SQL de producción o habilitación de runtime se deriva de este readback. PR #3359 DRAFT hasta decisión gobernada sobre su delta.

**Corrección principal:** el error 'se necesita una ruta nueva para ejecutar la evolución' queda **RETIRADO**. No era una dependencia del estado actual. Se preserva la evidencia pasada y solo se verifica el delta que no esté cubierto.

## Contraste atómico contra main — delta real y no repetición (2026-10-30)

**Base y conservación:** PR #3359 (`base=173088b756d79839bb1cb7b4ba63ee53bad389bc`). `main` avanzó 26 commits desde esta base, sin modificaciones a `profiles/systemic_root_cause_repair_lf/**`, `skills/profile_creator/**` ni `supabase/functions/run-creacion-perfil-lf/**` en esa comparación. No reabrir pruebas S26/WEB-001 que ya constan en ejecuciones COMPLETED 17/17; las nuevas comprobaciones aplican SOLO al delta.

### Delta SRCR real contra main
| Archivo/área | Estado respecto de main | Evidencia o acción |
|---|---|---|
| `SKILL.md` | Modificación propuesta | Niveles de búsqueda y terminalidad del caso; no incorporado |
| `validators/producer_depth.py`, `terminality_gate_v1.py` | Modificaciones propuestas | Controles de búsqueda/cierre; no incorporados |
| `evals/v05_producer_depth_cases.py`, `v08_gap_cascade_cases.py` | Modificaciones propuestas | Ampliación de pruebas existentes; no incorporadas |
| `evals/v09_exhausted_search_cases.py` | Archivo nuevo | Casos de exhaustividad; pendiente ejecución en revisión candidata |
| `judges/systemic_root_cause_semantic_judge.md`, `validators/validate_semantic_judge_result.py` | Modificaciones propuestas | Juez N1/N2 en el paso propio de SRCR; pendiente readback independiente real |
| `validators/validate_quality_receipt.py`, `materialize_quality_receipt.py` | Modificaciones propuestas | Enlazan validación a candidato y manifest; no incorporados |
| `evals/v10_n1_n2_quality_gate_cases.py` | Archivo nuevo | 10 casos declarados; pendiente ejecución exacta |
| `manifest.json` | Modificación añadida en este lote | Registra `evals/v08_gap_cascade_cases.py`, `evals/v09_exhausted_search_cases.py`, `evals/v10_n1_n2_quality_gate_cases.py` (35 a 38 referencias) |

**Verificación del parche:** 15 secciones, 12 archivos únicos, **23/23 hunks** aplican sobre `main`, sin conflictos de contexto/longitud; JSON del manifiesto candidato válido, sus tres referencias son únicas. Esto no es suite operacional ni aprobación semántica independiente.

### Delta transversal del Profile Updater — permanece candidato
- El caller `run-creacion-perfil-lf`, el guard SQL actual y el perfil runtime NO se modificaron en `main`; el PR conserva candidatos documentales en `docs/profile_updater/handoffs/**` que aún no están desplegados.
- Para adopciones futuras, `method_selection`/`evolution_decision` ya existen; `change_scope` y `deterministic_validation` deben comprobar la ubicación NATIVA a cada perfil, NO replicar paso 70.
- **Primera brecha material de seguridad:** el helper `_validate_n1_n2_audit` actualmente solo comprueba presencia de `independent_source_ref` y `independent_observed_at`, más coherencia de valores contra un manifest; eso NO certifica por sí mismo una consulta independiente. El juez deberá leer fuente real y `lf_profile_execution_trust_validation_v2` deberá enlazar un readback independiente acreditado dentro de la etapa `semantic_judge` existente. No declarar PASS solo con `readback://` o strings fabricados.
- Las pruebas WEB-001 y S26 completas ya ejecutadas corresponden a anteriores revisiones y NO dan automáticamente PASS a v09/v10 ni al nuevo enforcement de ubicación dinámica. Ejecutar solamente esos casos delta cuando el mismo updater consuma el candidato.

**Siguiente acción sin ruta nueva:** usar el Profile Updater ya operativo para consumir el parche corregido y resolver/validar este delta, con las llamadas/enforcement en los pasos NATIVOS de cada perfil. No abrir Router adicional ni repetir 17 etapas por diagnóstico. PR sigue DRAFT y sin edición de perfiles oficiales.

## Corrección de prueba independiente — mismo proceso (2026-10-30)

**Causa contrastada:** el nuevo control N1/N2 del candidato solo exigía `independent_source_ref`/fecha no vacíos y comprobaba valores contra el manifest del productor. Eso permitía marcar `PASS` con texto no ejecutado. No se debe atribuirle independencia real.

**Parche mínimo ejecutado solo en el handoff candidato:** el validador semántico existente para SRCR exige ahora un lector de fuente confiable `trusted_reader` recibido por el ejecutor de verificación existente, no desde el JSON del productor. Si la llamada no está conectada, añade `N1_N2_TRUSTED_READER_NOT_WIRED` y bloquea la aceptación N1/N2. El lector debe devolver valores, conteo, origen, digest, dato/nivel, revisión candidata y referencia de lectura; si divergen, devuelve `N1_N2_INDEPENDENT_READBACK_NOT_PROVEN`. No se creó un juez, paso ni pipeline nuevos.

**Efecto operacional previsto:** la llamada actual `validate_quality_receipt.py -> validate_semantic_judge_result.evaluate` no provee todavía ese lector y por tanto rechazará el nuevo PASS N1/N2. **Ese bloqueo es intencional para evitar auto-certificación**; conectar la comprobación fuente-real al ejecutor/guard existente y comprobar readback es parte del impacto pendiente, no un sistema nuevo.

**Evidencia del lote:** parche aplicado por simulación de hunks al `main` exacto: 23/23 hunk contexts/counts, 12 archivos en alcance, manifiesto con v08/v09/v10. Tres casos negativos nuevos agregados en v10: (1) sin lector confiable, (2) referencia ficticia con objeto aparentemente verificado, (3) valores falsificados en readback. Las pruebas nuevas de este cambio **no corrieron en el ejecutor oficial**; no declarar PASS funcional definitivo por aplicabilidad del parche.

**No repetir:** las anteriores 17 etapas completas y sus tests S26 / WEB-001 permanecen válidas para el alcance anterior. El nuevo conjunto de casos y la llamada fuente-real son exclusivamente delta. Mantener el mismo actualizador, sus puntos de decisión, sus llamadas y enforcement, con ubicación distinta según cada perfil.

**Siguiente acción concreta:** ejecutar solo los casos nuevos junto con readback independiente N1/N2 en el paso que corresponde a SRCR, confirmar que una referencia inventada no puede superar el juicio, y luego permitir que el actualizador retome únicamente el delta bajo sus controles actuales. Sin cambios en runtime oficial ni Supabase efectuados.

## Lote de enlace y pruebas nuevas — 2026-10-30

### Hallazgos comprobados, sin reiniciar procesos ni repetir S26/WEB-001
- El mismo runtime gobernado de ejecución SRCR `EXEC-PROFILE-GATE2-B6070E56727C1FB64437B850` permanece `IN_PROGRESS` con sus primeros nueve pasos registrados y `output_validate` (60) PASS. El siguiente gate natural es la revisión independiente ya existente, no abrir Router nuevo ni reejecutar el Updater.
- La salida de esa ejecución tiene refs de GitHub y evento Supabase, pero no un par de recibos N1/N2 acreditados en el ledger con el identificador de la misma ejecución; la consulta real del ledger devolvió **0** recibos coincidentes. El estado es `NO_VERIFICADO`, no `NO_EVIDENCE_FOUND`.
- Ejecutadas en Python local siete comprobaciones nuevas **sobre una reconstrucción del validador candidato**: 6/7 dieron el resultado deseado; una reprodujo el defecto de **falso PASS si un callback sintético devuelve un objeto completo idéntico**. No declarar suite 7/7 ni PASS independiente. El test positivo sintético no constituye consulta real.
- Lectura independiente de diagnóstico, con SELECT de solo lectura sobre las fuentes actualmente declaradas: N1 `public.v_lf_fuente_operativa_busqueda`, N2 `public.lf_activos`, filtrando por `PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF`: 1 registro en cada fuente; campos de identidad, nombre, estado documental/operativo y fecha coinciden; ambos readbacks SHA256 `5c76f435dfa66a789832e19a19facf3a2e4ef8b97c0791f42a249425341fd9f3`. Esta lectura **no quedó automáticamente anclada como recibo gobernado**, por lo que no autoriza el PASS del juez.
- El catálogo de resolutores existente tiene el proveedor Supabase con lectura SQL y digest del proveedor en estado ACTIVO/TRUSTED_PROVIDER_BOUND. El ledger `private.lf_evidence_ledger_v1` y su anclaje gobernado existen; no es necesario crear otra tabla, ejecución paralela ni proceso de calidad.

### Ajustes candidatos en el mismo flujo
- El chequeo N1/N2 deja de depender de un número congelado de versión del paquete; se dispara por la presencia de incertidumbres materiales en la salida. Se incorporó prueba negativa para versiones posteriores (sin salto silencioso de control).
- Se añadió al parche del perfil el enlace de pruebas de búsqueda, exhaustividad y revisión N1/N2 al validador **ya existente** del paquete. Antes figuraban solo en el manifiesto y no se ejecutaban automáticamente. Así se evita una prueba decorativa.
- Un borrador adicional `PROFILE_EXISTING_SEMANTIC_SOURCE_LEDGER_GUARD_CANDIDATE_20261030.sql` preserva el validador vivo y agrega dentro de la **misma revisión independiente** una comparación contra recibos `VERIFIED` del ledger de la misma ejecución, resolutor activo, dos niveles y datos/digest exactos. Sin recibo oficial o con datos desiguales: bloquear. Este SQL es **candidato en docs, NO materializado ni desplegado**.
- Validación estática del parche del perfil después de las correcciones: **24/24 fragmentos**, **13 archivos** sin conflicto contra `main`; esto verifica aplicabilidad, NO ejecución real de la suite ni cierre operacional.

### Condiciones explícitas para cierre de este delta
1. Confirmar readback de las fuentes N1/N2 emitido por el actor confiable del mismo proceso, no por la salida del modelo ni por el callback de prueba. La existencia de datos de origen se ha verificado solo en consulta de diagnóstico.
2. Que el guard existente compruebe el recibo oficial y rechace caso sin recibo/falso completo/consulta a otra versión; preparar cambio y materialización solo a través del Profile Updater ya autorizado y su train existente.
3. Ejecutar exclusivamente las pruebas nuevas de búsqueda y juicio, luego validar que el siguiente paso de la ejecución vigente no pueda registrar PASS con el recibo faltante; no repetir baterías históricas aprobadas.
4. Mantener las evaluaciones del sistema operativo y el juez semántico que ya existían, sin trasladar arbitrariamente el paso del perfil reparador a otros perfiles.

**Estado:** PR de candidatos DRAFT. Validación de fuente real diagnóstico PASS; parche aplicable PASS; evidencia independiente acreditada en ejecución = 0; prueba de falsificación = FAIL hasta instalar control del ledger. NO cerrar, no fusionar, no promover.

## Rectificación: grupos de evaluación y caso preexistente (2026-10-30)

**Readback del contrato, no inferencia:** `skills/profile_creator/validators/compare_s26_profile_evolution_v1.py` implementa dos grupos en la misma prueba de evolución: (1) 15 controles estructurales de contratos/validadores/ejecución y (2) casos operativos `PROFILE_OPERATIONAL_CASE_V1` con corridas vinculadas a hashes de árbol. `evolution_decision` (paso 37, `ACTIVE_ENFORCEMENT`) decide sobre la evaluación ya enlazada desde `method_selection` (35); `deterministic_validation` (90) y `regression_after` (110) contrastan el candidato después.

**Caso existente previo al nuevo trabajo:** `skills/profile_creator/operational_cases/systemic_root_cause_repair_lf/WEB-001.case.json`, con 9 controles y corridas BASE/CANDIDATE en `runs/`. Evidencia anterior de ejecución gobernada del updater: 15/15 estructura, WEB-001 de 4/9 a 9/9, `EVOLUTION_DEMONSTRATED`, 17/17 etapas. No crear un circuito alternativo, no decir que el sistema carece de un caso de evolución.

**Defecto específico N1/N2:** N1 y N2 son niveles internos de búsqueda de fuente (N1 vistas, N2 tablas canónicas) definidos en el caso de reparación SRCR; NO son los nombres del grupo estructural y operativo del updater. El handoff ya documenta exam11 del mismo WEB-001: salida válida con saltos de N1 y N5 no detectados. Los nueve checks WEB-001 existentes NO contienen aserciones sobre consulta N1/N2, sus valores, orden o readback. La medición oficial del 2026-10-30 (#3369; Actions 41088275460) devolvió `NO_UPDATE_REQUIRED`, S26 15/15, `operational.unmet_checks=[]`. Ese resultado se limita a los controles ya registrados y NO prueba que las nuevas condiciones N1/N2 se cumplan.

**Error de interpretación corregido:** no bloquear por 15/15 estructural, ni por `NO_UPDATE_REQUIRED` de una matriz que no mide el defecto, ni por permiso de invocación directa a Supabase. Primero evaluar la cobertura del caso preexistente y utilizar sus corridas/ejecuciones legítimas. La nueva propuesta `N1N2-001` en PR #3370 es un borrador añadido posteriormente y NO sustituye al caso original ni se considera autoridad activa. No usarlo para afirmar que recién nació el grupo operativo.

**Siguiente trabajo delimitado:** adaptar únicamente la cobertura de WEB-001 para comprobar la omisión real de N1/N2 y el readback que exige el cambio, preservando su historial y versiones, sin falsear resultados pasados. Ejecutar evaluación del mismo caso sobre el perfil vigente y sobre el candidato N1/N2, comparar por árbol exacto dentro del actualizador y registrar resultado en pasos 35/37/90/110. No reproducir automáticamente las 17 etapas completadas ni crear otro plan. Hasta medir el delta, no concluir falta de necesidad de actualización ni `EVOLUTION_DEMONSTRATED` para N1/N2.
