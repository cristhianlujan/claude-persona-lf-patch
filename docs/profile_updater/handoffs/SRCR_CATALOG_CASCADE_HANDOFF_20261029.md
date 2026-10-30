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
