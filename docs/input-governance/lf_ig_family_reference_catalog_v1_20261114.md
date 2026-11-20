# LF — herencia por referencia, catálogo run-independiente V1

**Propuesta técnica en PR, solo sandbox.** EKB/IG y #3940 revisados. Ninguna fuente ni política se modifica. El catálogo contiene solo ID/FK, alcance, SHA de la fila fuente y código de dictamen semántico; no incluye texto de regla, configuración de proveedor ni parámetros copiados, `run_id` o `pantalla_id`. El mapa `programacion.input_family_reuse_map_v1` sigue como evidencia histórica del run 956, sin lecturas operativas desde `public.lf_input_family_reuse_before_propose_v1`.

## Fuente SELECT verificada

- Run 956 (pantalla44, versión19): 17 PARTIAL / 30 COMPLETE. #3940: 11 transversales VIGENTE, 4 políticas mapeadas, 2 candidatas con casos, 0 cierre falso.
- Políticas: SECURITY #9 `SEC-B2B-IDEMPOTENCY` **CANDIDATO**, RATE_LIMIT #2 `RATE-B2B-UPLOAD` **CANDIDATO**, SESSION #1 `SESSION-B2B-DEFAULT` **VIGENTE**, TIMEOUT #2 `TIMEOUT-B2B-UPLOAD` **CANDIDATO**. Solo SESSION se incorpora; los 3 restantes quedan fuera hasta que exista fuente VIGENTE y QA.
- Pantalla44 `B2B-CARGA-002` y pantalla51 `B2B-AUTH-001` comparten `app_shell_code=B2B_APP_SHELL`, leído de `lf_ops.modulos`. Las fuentes CANAL se limitan a ese shell, no se proyectan a todos los usuarios.
- La conexión de inspección devuelve SQLSTATE **42501** al ejecutar las cinco funciones legadas de herencia/scope: no es evidencia de que no existan. Definiciones y firmas fueron leídas por `SELECT pg_get_functiondef`; el nuevo view las invoca con permisos de owner SQL, sin ampliar grants al inspector.
- Los ID 390,426,467,468,471,472,473,475,476 están en **CANDIDATO** y quedan fuera del catálogo. También se excluye la política candidata de anti-bot para Login; no hay promoción ni edición.
- `SEMANTIC_SELECTION_REQUIRED` en `lf_profile_native_bridge_prepare_v1` y `lf_profile_execution_input_validate_v1`: **0 apariciones** en la versión live; preparar e input_validate quedan intactas, sin parche innecesario.

## Dictamen individual: equivalencia del COMPONENTE heredable ≠ familia COMPLETE

| Familia | Fuente VIGENTE | Alcance | Equivalencia | Transferibilidad | Brecha residual que NO queda resuelta |
|---|---:|---|---|---|---|
| API_DATA_CONTRACT | regla 179 | GLOBAL | PARTIAL_BASE | TRANSFERABLE | Solo envoltura API; falta contrato ejecutable del endpoint de carga |
| ASSETS_ICONS | regla 362 | GLOBAL | PARTIAL_BASE | CONDITIONAL | Procedencia de asset no es inventario de iconos, falta 1 binding |
| AUDIT | regla 416 | CANAL B2B | EQUIVALENT_COMPONENT | TRANSFERABLE | Append-only; falta tabla de acciones auditables |
| DESIGN_SYSTEM | regla 387 | CANAL B2B | EQUIVALENT_COMPONENT | TRANSFERABLE | Consumo de tokens; quedan campos sin binding |
| LOADING_EMPTY_ERROR_STATES | regla 199 | GLOBAL | EQUIVALENT_COMPONENT | TRANSFERABLE | Estados básicos; falta casuística de cada paso |
| OBSERVABILITY | regla 412 | CANAL B2B | EQUIVALENT_COMPONENT | TRANSFERABLE | correlation_id; proveedor de runtime no está listo |
| PRIVACY_PII | regla 411 | CANAL B2B | EQUIVALENT_COMPONENT | TRANSFERABLE | Prohibición de PII en telemetría; quedan casos específicos |
| SECURITY | regla 396 | CANAL B2B | EQUIVALENT_COMPONENT | TRANSFERABLE | Deny-by-default post-auth; pre-auth se rige por AUTH |
| TESTING_OBLIGATIONS | regla 424 | CANAL B2B | PARTIAL_BASE | CONDITIONAL | Gate QA/producción no demuestra pruebas ejecutadas |
| VALIDATIONS | regla 25 | GLOBAL | EQUIVALENT_COMPONENT | TRANSFERABLE | Formato en servidor; faltan validaciones por campo |
| VISUAL_EVIDENCE | regla 370 | GLOBAL | EQUIVALENT_COMPONENT | TRANSFERABLE | Render revisado exigible; un asset sin evidencia actual |
| SESSION | política `SESSION-B2B-DEFAULT` #1 | CANAL B2B | EQUIVALENT_COMPONENT | TRANSFERABLE | Política central VIGENTE; falta vínculo/QA por pantalla |

**Importante:** estas son decisiones de equivalencia documental por comparación de títulos/descripciones y el alcance de #3940, no un juez de modelo independiente. Step70 exige una evaluación propia `LF_FAMILY_REUSE_INDEPENDENT_JUDGE_V1` con source_ids/hashes, razones y source_refs. El evaluador no se autoacredita independencia.

## Secuencia implementada en la migración

| Paso | Ruta / contenido | Seguridad |
|---|---|---|
| Catálogo | `programacion.input_family_inheritable_sources_v1` / `...members_v1` | 11 RULE + 1 SESSION; trigger rechaza CANDIDATO; membresía únicamente scope CONJUNTO_PANTALLAS |
| View | `public.v_lf_input_family_coverage_by_screen_v1` | Consulta 5 funciones existentes, calcula CURRENT/STALE contra hash de fila actual; no crea vínculos |
| Antes de propuesta | `lf_input_family_reuse_before_propose_v1` | Ya no depende de run956: fuente VIGENTE + scope, solo IDs/hash; conserva firma y devuelve CONTINUE, sin creación automática |
| 60 | `lf_profile_execution_canonical_read_judge_v1` y `lf_profile_native_bridge_record_output_v1` | V1 source válido; V2 sin texto copiado; V3 parámetros no duplicados; V4 sin regla duplicada si ya hay referencia; V5 gap sin solución/casos/pregunta cerrada → RETURN_TO_WORKER |
| 45 | `lf_profile_execution_context_admission_v1` | Admite `family_reuse_catalog` con ref, resumen y SHA, sin texto ni parámetros |
| 70 | `lf_profile_native_bridge_record_semantic_v1` | Compara evaluación independiente específica de equivalencia/transferibilidad. No fabrica recibo de modelo |
| 80 | `lf_profile_native_bridge_record_report_v1` | Solo fuente `source_id`, rule_id/policy_id, family_code y source_hash en recibo |
| 486 | `prepare_v1`, `input_validate_v1` | No se modifican: referencia antigua SEMANTIC_SELECTION_REQUIRED ya ausente |

Las funciones originales del resto de Input Governance (incluidas 64 lectoras de assessments), escritores de reglas (13), `lf_ops.reglas`, `reglas_pantallas`, `pantallas_politicas` y `programacion.input_family_assessments` NO son destinos de DML/DDL. Se mantienen las autorizaciones de lectura de service_role únicamente; anon y authenticated no reciben EXECUTE.

## PG dual y reversión

Test `test_family_reference_inheritance_pgdual_v1.py` con PostgreSQL 17.6/18.7, DDL real en BEGIN/ROLLBACK, 5 funciones originales congeladas obtenidas de pg_get_functiondef, 11 reglas de fixture vigentes y 1 política vigente. Prueba negativa de fuente CANDIDATO, pruebas V1–V5, equivalencia/transferibilidad mock explícita, STALE al mutar fixture de origen, fuente no vinculada, hash, y conservación de 47 assessments. Tras ROLLBACK: catálogo/view/funciones nuevas ausentes y fuentes restauradas. **No equivale a E2E real de Curator ni autoridad de un juez externo.**

Para revertir en sandbox después de aplicar por Train, usar PR de migración compensatoria con preimagen/hash exactos y evidencia de dependencias, no borrado directo ni SQL de inspección. La bitácora de migración del Train y los SHA almacenados son fuente de readback.

**Pendientes:** revisión semántica independiente de las 12 fuentes; validación E2E de cobertura en run nuevo; tres políticas candidatas excluidas; ninguna promoción ni escritura de reglas/políticas autorizada.
