# Análisis — RUN canónico A1–A9 con contexto de negocio (source-only)

Estado: **CANDIDATE / NOT_WIRED / NO_RUNTIME_ACTIVATION**. Rama aislada, sin SQL, despliegue ni autorización PG-01. Los cambios del PR solo afectan al binding candidato LF y al preflight; no habilitan SALY. Alcance aprobado: reutilizar el RUN de EJECUCION_PERFIL_LF e identificar cómo conservar la evidencia de Análisis.

## Autoridad y flujo

1. ACT-0001 clasifica y emite un handoff válido; **no reserva un RUN en cada consulta**.
2. `public.lf_profile_execution_begin_from_handoff_v1` valida handoff y delega en `public.lf_profile_execution_begin_v1`, que llama `public.fn_lf_operation_reserve_execution_v1`. La clave idempotente hace `RESERVED_NEW_EXECUTION` o `REPLAY_EXISTING_EXECUTION`.
3. Se conservan los once pasos transversales: `init_execution, router, profile_resolve, profile_source_read, input_validate, context_admission, research_baseline_freeze, execute_profile, output_validate, semantic_judge, report_output`.
4. El paso `input_validate` invoca Input Governance **solo cuando aplica**; puede reutilizar un RUN IG vigente o generar uno propio, referenciado desde el `execution_id` principal. No hay reingreso al Router por recuración.
5. Los pasos funcionales internos **A1–A9** pertenecen al perfil Análisis, no al Router ni a la definición transversal de once pasos. Deben producir recibos persistidos por la operación o su recorder autorizado, vinculados con el **mismo** `execution_id` y `request_sha256`.
6. `stage_trace` declarado por el LLM en el JSON final **no equivale** a nueve pasos materialmente recorridos. Un recibo propio del modelo jamás satisface por sí solo el paso.
7. Contrastar recibos por etapa, SHA exactos de la fuente A1–A9, currentness, RAW, juez independiente y eventual readback PG-01 antes de declarar cualquier READY.

## Parámetro obligatorio de negocio (`business`)

- **Variable canónica**: `business`, provista por ACT-0001 en `router_profile_handoff.business` y vinculada al mismo `execution_id`; **sin valor por defecto** y sin deducirla de palabras sueltas o tablas.
- El RUN conserva `business` en su manifest/contexto; las evidencias A1–A9 y RAW deben ser congruentes con el negocio del handoff. El preflight acepta la identidad exacta `execution.business == router_handoff.business == binding.business == stage_readback[].business == model_readback.business`.
- **LF (configuración del PR)**: el contrato candidato `profiles/programming_analysis_lf/contracts/analysis_source_binding.json` declara `business=LF` y `business_source_namespace=lf_ops`. Esto es un límite de alcance, no una autorización runtime. Las fuentes de pantalla/reglas se resuelven únicamente desde autoridades LF vigentes.
- **SALY (fuera del alcance de activación)**: Supabase contiene esquema `saly`, pero sus tablas/consultas/autoridades aplicables a Análisis **no están verificadas ni vinculadas** al Router/profile runtime actual. El preflight rechaza SALY cuando se le pasa binding LF o binding SALY sin estado de autoridad `CURRENT_RELEASED`; no consulta ni interpreta `lf_ops` como respaldo.
- El Router `public.lf_router_profile_execution_handoff_v1` verificado en vivo actualmente exige `p_business='LF'`; **este PR no cambia esa política**. Para SALY futuro, el owner del Router deberá proporcionar soporte gobernado, manifest/authority de negocio y perfil/capacidad aplicable antes de iniciar RUN.
- Las funciones SQL, selecciones de pantallas y consultas son responsabilidad de los resolvers/adapters canónicos específicos del negocio; nunca `if business=='SALY': usar tabla inventada`. No introducir segundo Router, segundo RUN, lógica global acoplada a `lf_ops`, ni fallback cruzado.

**Control negativo obligatorio**: petición SALY + binding LF, consulta/table source LF, `business` perdido o alterado durante el recorrido, o binding SALY sin currentness/autorización: `BLOCKED` antes de inferencia, sin declarar READY.

## Cierre técnico 10.1 — clasificación inicial (no activación)

| Input tipificado | Salida 10.1 | Siguiente acción |
|---|---|---|
| CREATE | NEW_CANDIDATE | 10.2 fuentes |
| EVOLVE | EXISTING_EVOLUTION_CANDIDATE | 10.2 fuentes |
| COMBINE | MIXED_CANDIDATE | 10.2 fuentes |
| REPAIR | REPAIR_HANDOFF | RETURN_TO_ROUTER, sin invocación directa |
| UNKNOWN | NEED_MORE_EVIDENCE | Clarificar intención |

10.1 requiere `business=LF`, `execution_id` ya reservado, literal original y `request_sha256` coincidentes, intención tipificada y refs de origen. El clasificador determinista no ejecuta SQL ni clasifica por regex sobre palabras del usuario. El tipo devuelto es provisional y distinto de `authority_state` y `implementation_state`, que se determinarán por evidencia en 10.2–10.4. Reglas documentadas `B2B-AUTH-001` existentes no prueban implementación de login.

**Ejecución y verificación:** 18/18 controles de clasificador `unittest` locales, con hash Git blob idéntico al archivo en GitHub (clasificador `9fe3531ce5cdcf6b82af71a4b0aae614fc46cbe3`, tests `a21686d503118565114e7a9f3a574b0e2b606fee`). El paquete de modelo candidato exige campos `initial_intent_kind`, `initial_development_class`, `initial_evidence_refs` y rechaza READY ante REPAIR/UNKNOWN; no se presume ejecución de los controles extra del paquete sin evidencia independiente.

**Criterio de cierre:** `10.1_SOURCE_AND_LOCAL_TESTS=PASS`, `10.1_GOVERNED_RUN_READBACK=NOT_TESTED`. No escribir PASS operacional ni continuar acreditando 10.2/10.3 por este dictamen. Perfil `CANDIDATE_NOT_RELEASED`; sin merge, sin SQL ni despliegue.

## Dos numeraciones diferentes

| RUN externo `EJECUCION_PERFIL_LF` | Interno Análisis |
|---|---|
| 00 init_execution; 10 router; 20 profile_resolve; 30 profile_source_read | A1 / paso funcional 10 (comprensión) |
| 40 input_validate; 45 context_admission; 47 research_baseline_freeze | A2–A8 / pasos funcionales 20–80 |
| 50 execute_profile | A1–A9, materializados y trazados bajo este RUN; no nueve RUN nuevos |
| 60 output_validate; 70 semantic_judge; 80 report_output | A9 / paso funcional 90 (handoff; no PG-01 automático) |

## Preflight de contrato — NO es una integración

`profiles/programming_analysis_lf/evals/analysis_stage_receipt_preflight_v1.py` verifica estructura y vínculo interno de un **paquete armado de readbacks**. `test_analysis_stage_receipt_preflight_v1.py` contiene controles positivos y negativos. Incluso un positivo devuelve solo `STRUCTURAL_CANDIDATE_ONLY` y `operational_ready=false`: referencias autodeclaradas no son autoridad independiente.

## Evidencia de fuentes, 31-10-2026

Git `main` inspeccionado: `7b9cf78fbccfea5992174cd66d311858f9cb5af1`. Los nueve Git blob SHA de `contracts/analysis_source_binding.json` coinciden 9/9 con las fuentes de main. **Existencia y coincidencia de blob NO prueban currentness externo, consumo del modelo ni RUN operativo.**

EKB: `PROGRAMMING-ANALYSIS-STAGE-SOURCE-ATTESTATION-GAP-001`, `PROFILE-RUNTIME-GOVERNED-STEP-BYPASS-001`, `PROGRAMMING-ANALYSIS-A14-EVIDENCE-TIER-FALSE-READY-001`, `PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001`.

## Checkpoint progresivo A1–A9 dentro del RUN (candidato)

Se verificó en Supabase que `public.fn_lf_operation_checkpoint_v1(execution_id,lease_owner,lease_fence,checkpoint_seq,checkpoint_payload,actor_execution_id)` ya implementa control de lease/fence, secuencia monotónica y replay idempotente. No crea RUN nuevo. Su campo `checkpoint_payload` conserva la **última** versión; por eso cada nuevo checkpoint debe acumular las evidencias precedentes sin sobrescribirlas.

- El archivo `profiles/programming_analysis_lf/evals/analysis_stage_checkpoint_prepare_v1.py` **solo prepara** el snapshot acumulativo de A1–A9; no consulta ni modifica la base. Su salida `persisted=false` y `operational_ready=false` es invariante.
- El consumidor, cuando quede vinculado, debe recuperar el `execution_id` exacto creado desde handoff, proyectar explícitamente `business` desde el manifest/handoff del Router (el ledger no tiene una columna `business`), obtener el lease canónico vigente, resolver la fuente CURRENT y capturar **una observación genuina por etapa**.
- Solo entonces llama la función de checkpoint existente con seq siguiente; lee de vuelta `checkpoint_seq`, `checkpoint_payload`, `execution_id` y comprueba el snapshot **completo** del mismo RUN. Ni la preparación local ni un campo `stage_receipts` escrito por el modelo prueban que persistió.
- Cada observación debe venir del productor real con identidad, evidencia RAW de ese hito, timestamp y fuente inmutable. **Prohibido transformar un único resultado final que declara A1–A9 en nueve supuestas ejecuciones históricas**. Si el runtime solo produce un RAW final, ese RAW debe etiquetarse como resultado único, no como nueve receipts operacionales.
- Input Governance sigue siendo condicional y su propio run/recibo se enlaza al mismo RUN principal. SALY requiere su propio binding y fuente; no se permite inferir LF de un esquema por defecto.
- El preparador valida estructura y orden; no acredita la procedencia, el timestamp, el actor autorizado, la autenticidad de la fuente o el modelo. Esas verificaciones son obligaciones del **consumidor y juez independientes** antes de cualquier PASS.
- El recorder de once pasos `lf_record_profile_execution_step_v1` permanece intacto: insertar A1–A9 como `step_id` nuevos allí rompería los contratos compartidos. El único mecanismo aquí propuesto para progreso es el checkpoint ya existente.

**Acceptance E2E pendiente**: Router real → RUN reservado → lease vigente → cada etapa con evidencia del productor y fuente actual → checkpoint persistido → readback por etapa → RAW final → output validator → juez independiente → cierre gobernado. Este PR no integra ese consumidor, no cambia Supabase y no ejecuta esta prueba.

## Paso 10.2 — localización de fuentes y auditoría E2E (2026-10-31)

**Contrato fuente y receptor candidato:** `contracts/analysis_10_2_source_reception_v1.json`, `validators/analysis_10_2_receive_v1.py`, `evals/test_analysis_10_2_receive_v1.py`. Se añaden como requerimientos del perfil `contracts/runtime_binding.json` y en `definition_source_reception` del schema/modelo. El resolver de fuentes real será `SOURCE_RESOLUTION_POLICY / TYPED_DATA_ACCESS` y `CURRENTNESS_AUTHORITY`, transportado por adapters existentes. **Ninguno de estos archivos consulta Supabase, registra RUN o produce receipt runtime.**

### Evidencia localizada directamente (read-only)

- Negocio `LF`, fuente `lf_ops.pantallas`: pantalla `B2B-AUTH-001` (`id=51`), estado `CANDIDATO`, versión `v0.5`, decisión `DEC-B2B-HANDOFF-SCREEN-PACKAGE-001`, 71 reglas directas relacionadas en `lf_ops.reglas_pantallas`, 38 vigentes.
- Source lookup de prueba via read-only SQL **no** equivale al source receipt del adapter del perfil, ni a CURRENTNESS o autorización 10.3.
- El receptor soporta targets tipados (`SCREEN`, `MODULE`, `RULE`, etc.) del resolver, sin fijar B2B; exige identidad `business=LF`, `execution_id` y `request_sha256` iguales al resultado 10.1, `sender_payload_sha256` exacto, target type/code exactos, refs de fuentes y reglas cuando existan.
- Rechaza SALY/LF cruzado, hash alterado, RUN distinto, resultado 10.1 bloqueado, target equivocado, ausencia de source receipt; si recibe fuente válida marca únicamente `RECEIVED_CANDIDATE`, `source_currentness=NOT_ATTESTED`, `persisted=false`, `operationally_verified=false`.
- Pruebas locales ejecutadas: 21/21 `unittest` PASS con fixture sintético, receptor byte-identical Git blob `de81274fd87085f7bc276372c5c757afeb138e8f`; tests del repo incluyen los 21 escenarios, pero su Git blob exacto no es el de la copia local y no se afirma test exact-head CI.

### Comprobación solicitada: recorrido real (lecturas Supabase)

| Punto | Readback real | Dictamen |
|---|---|---|
| ACT-0001 | solicitud literal de desarrollar Login B2B -> `BLOCKED / BLOCK_ASSET_TYPE_UNRESOLVED`; `candidate_basis=LEXICAL_TOKEN_OVERLAP_NOT_IDENTITY_NOT_AUTHORITY`; no downstream | **FAIL** |
| Registro de perfil de Análisis | `public.lf_activos` con `PERFIL-PROGRAMMING-ANALYSIS-LF`: **0 registros** | **NO** |
| Adapter Router para Análisis | `public.v_lf_router_adapter_bindings` con target `PERFIL-PROGRAMMING-ANALYSIS-LF`: **0 filas** | **NO** |
| RUN oficial | `public.lf_operation_execution` con `operation_code=EJECUCION_PERFIL_LF` y `target_code=PERFIL-PROGRAMMING-ANALYSIS-LF`: **0 filas** | **NO CREADO** |
| Persistencia de A1–A9 | `checkpoint_payload ? 'analysis_stage_progress_v1'` en cualquier RUN: **0 filas** | **NO** |
| Pasos externos asociados | JOIN `public.lf_operation_execution_steps` por target del perfil Análisis: **0 filas** | **NO** |
| Transferencia 10.1→10.2 | Sin RUN/step upstream, no receipt de transporte ni lectura del consumidor | **NO EJECUTADA** |
| Recepción real 10.2 | Receptor probado sobre fixtures sintéticos; no recepción del runtime ni registro | **NO ACREDITADA** |

**Conclusión verificable:** `10.2_SOURCE_AND_LOCAL_TESTS=PASS` (source-only), `10.2_END_TO_END=BLOCKED`. La operación `EJECUCION_PERFIL_LF` tiene RUN de otros perfiles, pero no son prueba de Análisis. No mezclar pruebas de código con ejecución de perfil. Ningún RUN fue creado en esta investigación (solo SELECT y lectura de fuentes). No declarar paso 10.2 cerrado gobernadamente.

**Cadena mínima para remediar:** corregir tipificación/selección ACT-0001 por procedimiento transversal, registrar y autorizar perfil Análisis como `CURRENT RELEASED` solo tras sus gates de calificación, vincular el adapter de fuentes LF, reservar un RUN real idempotente, ejecutar 10.1 y registrar checkpoint con lease, transmitir payload/fingerprint a 10.2, emitir source receipt tipado y readback en el **mismo** RUN, juez independiente y validación 10.3. Sin ese readback, stop.

## Pendientes de implementación en su dueño canónico

- Registrar/autorizar el activo `PERFIL-PROGRAMMING-ANALYSIS-LF` en las capas gobernadas, sin activarlo en producción.
- Conectar **un recorder existente** a cada checkpoint A1–A9; investigar el soporte de readback preciso antes de elegir almacenamiento. No insertar falsos recibos ni sobrecargar el RUN transversal con pasos universales A1–A9.
- Corregir vínculo real Router/run/modelo de la cola que hoy puede omitir la operación gobernada; readback antes de inferencia.
- Implementar un comprobador independiente que lea cada recibo desde su fuente (no solo acepte URIs), verifique currentness/issuer/identidad/digest y evalúe utilidad del resultado.
- Ejecutar 3 casos reales en no-producción con positivos y negativos, y PG-01 solo cuando corresponda. No declarar A16Q_C2/C3 DONE por un test local.

No merge ni paso a producción hasta revisión de los contratos, tests y prueba del consumidor real.