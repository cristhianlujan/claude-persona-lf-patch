# LF — Solicitud de revisión independiente PR #3427

**Rol del lector:** revisor independiente, no productor ni reparador. **Permisos para esta revisión:** solo lectura de GitHub y Supabase. No hacer merge, no autorizar runtime, no alterar fuentes, contratos ni registros. **Ámbito:** normalizar la comparación funcional de versiones por cada problema material, sin cambiar el veredicto oficial del comparador.

## Identidad y lectura obligatoria

- PR: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3427
- Repo: `cristhianlujan/claude-persona-lf-patch`.
- Leer HEAD actual del PR y congelar su SHA; **no utilizar un SHA previo sin releer el HEAD**.
- Revisar **diff completo**, especialmente:
  - `skills/profile_creator/validators/operational_coverage_v1.py`
  - `skills/profile_creator/operational_cases/systemic_root_cause_repair_lf/WEB-001.case.json`
  - `sandbox/lf_contract_gate_test/profile_execution_runtime/test_profile_problem_comparison.py`
  - `sandbox/lf_contract_gate_test/edge_function_operation/test_profile_problem_comparison_lane.py`
  - `docs/profile_updater/PROCEDIMIENTO_COMPARACION_EVOLUTIVA_POR_PROBLEMA_20261031.md`
  - `docs/profile_updater/README.md`.
- Leer el comparador `skills/profile_creator/validators/compare_s26_profile_evolution_v1.py` y su consumidor del resultado `operational`.
- Consultar `public.lf_policy_versions`, código `POL-PROFILE-UPDATE-PASS` activo; al prepararse este handoff constaba versión `v1.4-evolved-routing-candidate`, SHA `5ae6804ded17dea94a7ec2d8c4ebe588b1017222ab8d92b912bc8607996892b5`. **Reconsultar SHA vigente.**
- Revisar los contratos de pasos 90 `deterministic_validation`, 100 `semantic_judge`, 110 `regression_after`, 130 `report_output` en Supabase, estado y tipos de evidencia.

## Objetivo y criterios

Verificar que el **mismo problema** tenga respuesta del perfil `original`, respuesta del perfil `evolved`, referencia recuperable al RAW, evidencia, diferencias y juicio semántico separado. El método debe permitir reconocer mejoras **de diagnóstico, investigación o decisión** aunque siga bloqueada una reparación sin autoridad o consumidor demostrados; no debe premiar mayor verbosidad.

Para cada problema usar la clasificación `MEJORA_OBSERVADA / MEJORA_VERIFICADA / CONSERVADO / SIN_MEJORA / REGRESION / NO_VERIFICADO`; el nuevo proyector **NO** genera por sí mismo esta decisión, que corresponde al juez semántico independiente. Distinguir este juicio del contador tipado y del gate `EVOLUTION_DEMONSTRATED`.

## Pruebas independientes mínimas

1. Confirmar contra `main` que los 14 `checks[]` y el comparador `compare()` siguen intactos; no asumirlo por título/CI.
2. Verificar que la `comparison_dimensions[]` de WEB-001 contiene **dos** problemas y sus punteros/controles están respaldados por el caso; no convertir esos dos problemas en lista universal para otros perfiles.
3. Ejecutar tests positivos, negativos y análisis de código: falta de RAW, inputs distintos, `RUNTIME_ATTESTED` declarado pero no verificado, duplicados, ruta RAW inyectada, controles `if_then` ejercitados parcial o nulamente; revisar que el reporte no modifica gates.
4. Comprobar `raw_file_ref`: proviene de la ruta del archivo dentro del trusted root, no de un campo que el propio RAW declare; comparador no se ve afectado por metadatos de trazabilidad.
5. Revisar el tamaño de salida del reporte y los límites del consumidor GitHub Actions / ledger de Supabase; detectar truncamiento, colisión de IDs y posibles cambios inadvertidos del diccionario de salida.
6. Verificar trazabilidad **de verdad**: el perfil anterior de referencia `RUN-WEB001-CANDIDATE-20261029.json` no tiene `input_literal`; el evolucionado de referencia `WEB001_GPT_NATIVE_CANDIDATE_RUN_UNADMITTED_20261031.json` tiene `attestation=NONE`, está fuera del trusted root y no es corrida fría. **Estos dos registros permiten solo comparación preliminar, no prueba pareada formal.**
7. Releer evidencias operativas con Supabase: `ACT-0058.owner_name IS NULL`, condición `failed_retry` declarativa `retry_count > 3` vs SQL `retry_count+1 >=3` y fuente del consumidor de reingreso aún no acreditada. Evaluar si hay ganancias semánticas en los dos problemas.
8. Verificar que el reporte del nuevo método no suplanta `semantic_judge`, ni un RAW simulado se cuenta como ejecución genuina. Sin segundo orquestador/adapter, sin SQL ni permisos nuevos.
9. Ejecutar CI de HEAD exacto: carril `LF Edge Operation R17 Tests` y `PASE` y comprobar resultado de tests, no solo estado del workflow.

## Antecedentes y estado sin inventar

- 2/2 problemas WEB-001 muestran **MEJORA_OBSERVADA** según contraste anterior; no hay `MEJORA_VERIFICADA` ni comparación oficial certificada.
- Los RAW de referencia arrojan 9/14 frente a 14/14 sobre los 14 predicados, **pero OP14 pasa vacuamente en evolved** por `authority_kind=UNKNOWN`; no declarar investigación derivada completa a partir de OP14.
- Hallazgos del productor corregidos en la rama: no equiparar atestación declarada a verificada; contar antecedente condicional; columnas `original/evolved` con punteros; marcar referencial del RAW trusted derivado por loader.
- Las pruebas y PASE **no son revisión independiente**. Leer resultados nuevos para el HEAD actual.

## Formato de dictamen esperado

Tabla `id | requisito | evidencia exacta | anterior | evolucionado | evaluación | severidad/bloqueo`, con mínimo 2 problemas de WEB-001 y los 14 controles preservados. Entregar `APROBADO / CORREGIR / BLOQUEADO_EVIDENCIA`, identificando pruebas ejecutadas, claims inválidos, riesgos, recomendación y próximos pasos. **No** hacer merge ni publicar aprobación automática del productor.

**Dependencias:** PR #3420 (matriz de destino dinámico), #3399 (perfil candidato Reparador), #3412 (enmienda del candidato). No sustituye sus aprobaciones ni la comparación con dos inferencias nativas frescas.


## Continuidad tras dictamen independiente BLOQUEADO_EVIDENCIA (31/10/2026)

El propietario trasladó un dictamen independiente `BLOQUEADO_EVIDENCIA`, referido al HEAD anterior `b260f047bdc2c5f8908f4d9105fa8a79885ac881`. **No considerarlo aprobación del HEAD nuevo.**

El productor reparó de modo acotado en la **misma rama**:
1. `conditional_controls_all` emite aplicabilidad real de **los cuatro** controles condicionales WEB-001 (OP03, OP05, OP06, OP14), aunque no estén asignados a `control_ids` de un problema.
2. `raw_file_sha256` de bytes del archivo realmente leído por el loader y `raw_source_commit_sha=null` mientras no se confirme el commit Git. No falsificar procedencia.
3. Vista acotada para múltiples problemas, RAW y campos, con `PARTIAL_SOURCE_LOOKUP_REQUIRED` y contadores de elementos omitidos; nunca confundir vista parcial con evidencia total.
4. Pruebas adversariales adicionales para condiciones, límites y hash del RAW. Confirmar las pruebas en el HEAD de revisión; no reutilizar CI previo.

**Verificar nuevamente:** semántica del método (2 problemas), 14 controles idénticos, resultado del comparador oficial inalterado, SHA de caso fuente, compatibilidad de `operational` en el consumidor, límites de payload, no fabricación de commit, no autorización automática y dictamen independiente por el HEAD final.

**Bloqueos NO levantados por estas correcciones:** dos ejecuciones nativas con igual entrada certificadas, juez semántico independiente, paridad Router/directo y transporte E2E a pasos 100/110/130. El merge sigue bloqueado hasta resolverlos; PR #3420 (matriz de destino dinámico) tampoco se considera integrado solo por existir.
