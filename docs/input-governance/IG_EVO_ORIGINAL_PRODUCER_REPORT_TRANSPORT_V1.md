# LF IG — Transporte de informes originales del Curator y R1–R6

**Estado:** implementación candidata / NO-GO. No valida resultados semánticos ni ejecuta los detectores nuevamente. 
**Arquitectura inalterada:** Router ACT-0001 → Perfil → Input Governance (Curator → Validator) → Perfil. No crear una ruta B, otro judge, otro worker, cola ni motor.

## Alcance y fuente de verdad

Los productores reales encontrados en código vigente son:
| Emisor | Función existente | Resultado original y ubicación |
| --- | --- | --- |
| Curator | `programacion.fn_input_governance_curator_materialize_v1` | Envelope JSON completo retornado (status, estrategia, recibo, `proposal_materialization`, rendimiento y contexto) |
| R1 | `fn_ig_evo_r1_parameter_provenance_v1` | `proposal_materialization.ig_evo_r1_diagnostics` |
| R2–R6 | `fn_ig_evo_r2_r6_diagnostics_v1` | `proposal_materialization.ig_evo_r2_r6_diagnostics`; los tipos R2/R3/R4/R5/R6 se conservan **como los emite el detector agrupado**, sin fabricar llamadas individuales |
| G1 | `fn_ig_evo_rule_graph_inventory_v1` | `proposal_materialization.ig_evo_graph_index[].raw_graph`: salida entera por **cada regla efectiva elegible de la pantalla**, del mismo `g.doc` que produce G1, sin re-ejecutar para transporte |
| Validator | `input_family_assessments.validator_*` y recibo Curator→Validator existente | No se modifica su proceso; se conserva evidencia y dictamen por el mecanismo ya vigente. Aún no se certificó un RAW de Validator de extremo a extremo |

**Cobertura G1 corregida (dentro de la autoridad vigente):** la selección de raíces es independiente de R6. El inventario parte de **todas las reglas efectivas elegibles de la pantalla** usando la fuente canónica `programacion.fn_input_effective_rule_links_v1(pantalla_id,'INPUT_GOVERNANCE')`, sin `DERIVED_GLOBAL`, y las reglas en estado `VIGENTE` o `CANDIDATO`. El mismo contrato de elegibilidad ya se aplica dentro de `fn_ig_evo_rule_graph_inventory_v1`. Se eliminan `LIMIT 8` y cualquier tope fijo de raíces: **`graph_captured_root_count = graph_eligible_rule_count`** es obligatorio. Cada `raw_graph` es el mismo `g.doc` calculado una vez, no un nuevo escaneo para transportar.
  
**Ejemplo de readback:** `B2B-AUTH-001` (id 51), 2026-11-07: el catálogo de vínculos devuelve **283 reglas distintas**, de las cuales **71** están ligadas a la pantalla por fuentes admisibles de G1 (`LEGACY_EXPLICIT=69`, `DECLARATIVE_APPLICABILITY_V1=2`; de ellas, 38 `VIGENTE` y 33 `CANDIDATO`). Las otras **212** son vínculos `DERIVED_GLOBAL`: **no tienen atestación de aplicabilidad específica a esta pantalla** y la función G1 existente no permite analizarlas como raíces. **No afirmar cobertura de las 283.** Se informa explícitamente `graph_total_linked_rule_count`, `graph_eligible_rule_count`, `graph_derived_global_unattested_count`, estado `UNATTESTED_SCREEN_APPLICABILITY_NOT_G1_ROOT_ELIGIBLE` y referencia canónica de recuperación. Son conteos dinámicos; los números anteriores solo ilustran el readback de ese día.

G1 sigue teniendo límites internos de exploración por raíz (128 nodos / 512 referencias) y una profundidad máxima de 5; `graph_limit_hit=true` implica contenido incompleto y requiere remediación, sin declarar una evaluación semántica satisfactoria. Los dos estados de transporte son `ALL_G1_ATTESTED_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS` y, si algún grafo interno se trunca, `ALL_G1_ATTESTED_RULE_ROOTS_CAPTURED_WITH_INTERNAL_TRUNCATION` (con IDs de reglas afectadas).

**Límites operativos:** no reemplazar ocho por otro máximo numérico sin métricas. Medir tiempo, memoria, privacidad y tamaño de JSON con RUN nuevo y sus 71 reglas; si se requiere partición por transporte, no descartar ninguna raíz ni recalcular las ya generadas.

## Captura una sola vez por RUN

- En la respuesta final `v_full_original_response` del mismo Curator, persistir `programacion.input_governance_producer_raw_v1.original_curator_output` y su SHA-256 calculado sobre **el mismo valor original JSONB** (sin normalizar a sinopsis). `producer_original_sha256` incorpora SHA-256 independientes de CURATOR, R1, R2–R6 y G1 extraídos del JSON almacenado, sin ejecutar una nueva investigación. Para el productor ausente conserva `null` y su `producer_emission` explica la causa.
- `run_id` es PK; no sobrescribir el RAW anterior ni mezclar RUN. Registrar pantalla, identidad del Curator y `source_snapshot_sha256`.
- Solo se inserta para `BOOTSTRAP`, `REBIND`, `SOURCE_STALE_RECURATE` y `FULL_RECURATE`. `NOOP` **reutiliza** el informe previamente guardado; no lo recalcula.
- Para `REBIND`, no inferir por el nombre que los detectores se emitieron: el escritor `fn_input_governance_curator_rebind_v1` puede delegar a recuración si cambia el contrato. Verificar `proposal_materialization.ig_evo_r1_diagnostics`, `ig_evo_r2_r6_diagnostics` y `ig_evo_graph_index` **en el RAW realmente devuelto**. Si ninguno se emitió, `ORIGINALS_NOT_EMITTED_FOR_REBIND`, con `producer_emission` por componente.
- Diferenciar el RAW actual del RUN y el RAW de su predecesor. `source_lineage` registra `parent_run_id`, disponibilidad de archivo anterior y estado de equivalencia de snapshot. **Incluso con snapshot idéntico, R2–R6 puede incluir run_id y comparación histórica propios; no copiar automáticamente evidencia del RUN anterior como si fuera del nuevo.** Reutilización histórica no acreditada permanece bloqueada, sin reejecutar investigación.
- El snapshot de fuentes puede sellarse después del Curator, durante el avance al Validator. Capturar `universe_snapshot_sha256` del RUN y el hash del envelope; validar siempre identidad/screen/Curator/universo, y si el hash de fuentes era nulo al capturar pero se completa después, reportar `PINNED_AFTER_CURATOR_CAPTURE` en vez de interpretar un falso drift. Si ya estaba presente y cambia, **bloquear**.
- Los RUN anteriores a esta migración devuelven `NOT_CAPTURED_LEGACY_RUN`; **no ejecutar de nuevo R1 ni Curator para rellenarlos**.

## Comportamiento verificado de estrategias (antes del Validator)

| Estrategia | RUN | Investigación R1–R6/G1 | Informe actual | Criterio de trazabilidad |
|---|---|---|---|---|
| `BOOTSTRAP` | Nuevo | Sí, mediante el materializador | `ORIGINALS_CAPTURED` si emitió los tres grupos | Snapshot/universo y SHA del RAW |
| `FULL_RECURATE` | Nuevo | Sí | `ORIGINALS_CAPTURED` si emitió los tres grupos | Diferenciar RUN nuevo de antecedentes |
| `SOURCE_STALE_RECURATE` | Nuevo | Sí | `ORIGINALS_CAPTURED` si emitió los tres grupos | Cambios de fuente con evidencia |
| `REBIND` | Nuevo | Normalmente no; puede delegar a recuración | `ORIGINALS_NOT_EMITTED_FOR_REBIND` si no produjo R*, o `ORIGINALS_CAPTURED` si los emitió | No copiar RAW de padre por inferencia |
| `NOOP` | Mismo RUN | No | Archivo original del mismo RUN, si existe; sino `NOT_CAPTURED_LEGACY_RUN` | No ejecutar detectores para completar |
| `BLOCK` | Ninguno nuevo | No | No se crea recibo RAW | Preservar bloqueo y razón |

El estado `ORIGINALS_CAPTURED` exige JSON R1, R2–R6 **y G1 como array**. El simple registro del envelope del Curator no prueba que se hayan emitido todos los productores. Los indicadores de fuente y emisión **no** representan calidad semántica ni implementación validada.

## Etapa 7 — Consolidación de Input Governance (candidata, antes del Perfil)

La función oficial `programacion.fn_input_governance_execute` continúa seleccionando el RUN, ejecutando los EKB/freshness gates y calculando **una única vez** su `stage_gate` y decisión de readiness. La migración candidata agrega únicamente un ensamblador de **lectura** `programacion.fn_input_governance_original_consolidate_v1(run_id,stage_gate)`; no es una llamada a Curator, Validator, R1–R6 o G1. La ejecución existente adjunta `ig_consolidated_original_reports` **al final de su respuesta**, sin alterar `status`, `predecision_crosscheck`, `promotion_authorized=false` ni `production_authorized=false`.

| Material original | Procedencia | Transporte propuesto |
|---|---|---|
| Curator / R1 / R2–R6 / G1 | Archivo inmutable `input_governance_producer_raw_v1` del mismo RUN | `curator_originals.original_curator_output` íntegro + SHA + estado de emisión de cada productor |
| Validator por familia | Fila almacenada `input_family_assessments` | `validator_original_rows[].original_assessment_row` sin cambiar estados/finding/hash |
| Aserciones del Validator | `input_validator_assertion_sets_v1` por `assertion_set_sha256` | `validator_evidence_logical_rehydrated`, recuperado con el helper ya existente y verificado frente al **`validator_sha256` original** |
| Estado del RUN y fuente | `input_readiness_runs` | `run_id`, pantalla, `source_snapshot_sha256`, `universe_snapshot_sha256` |
| Readiness | `stage_gate` oficial ya calculado | `full_qa_stage_closed` y `full_production_stage_closed`, más estados de cada fila original |
| Semántica | `scope.validator_semantic_mode`, política del RUN | Campo literal `SOURCE_INTEGRITY_ONLY` cuando corresponda; **`independent_semantic_judgement_here=NOT_TESTED`**, `semantic_promotion_authorized=false` |

**Controles de bloqueo:** fuente vigente, stage-gate de ese RUN, cardinalidad exacta de familias, `validator_outcome=PASS` como resultado **original**, existencia del archivo de aserciones, `curator_sha256`/snapshot coincidentes, SHA-256 del recibo Validator reconstruido exactamente con la fórmula del guard oficial. Si falla algo de la evidencia del Validator, el ensamblado lanza error y **no inventa el informe**. Si el informe del Curator es legado/no emitido, el resultado lo declara `VALIDATOR_EVIDENCE_PRESENT_CURATOR_ORIGINAL_INCOMPLETE` y `ig_original_reports_complete=false`; **no lo reconstruye ni lo confunde con un informe completo**.

**Alcance comprobado en READBACK histórico RUN 949 (no prueba del candidato):** 47 familias con `PASS` de integridad; 47 conjuntos de aserciones almacenados (23 SHA distintos, 47 aserciones `SOURCE_INTEGRITY`), 24 QA BLOCKED y 25 de producción todavía abiertas. La existencia del registro no demuestra un transporte de bytes ni consumo del modelo.

**Gates pendientes:** compilación PostgreSQL del SQL candidato, positivos/negativos, SHA exacto al rehidratar, volumen/latencia y privacidad del JSON completo, autorización interna SQL, `source_snapshot` posterior a Curator, G1 con 71 raíces, recibo de transporte al modelo. **No calificar de E2E/PASS ninguna de estas comprobaciones**.

## Transporte por el camino existente

```text
Curator original (incluye R1, R2–R6 y G1 emitidos)
  └─ archivo inmutable por RUN / SHA
Validator: filas originales + archivo de assertions por SHA
  └─ rehidratación del Validator sin volver a ejecutarlo
     └─ fn_input_governance_original_consolidate_v1(run_id,stage_gate)
        └─ fn_input_governance_execute (respuesta oficial; decisión intacta)
           └─ ig_consolidated_original_reports (contrato propuesto)
              └─ Perfil: ÚLTIMA ETAPA, integración/E2E todavía NO probados
```

La función lectora es interna (`SECURITY DEFINER`, sin `EXECUTE` para PUBLIC, anon, authenticated ni service_role). El perfil obtiene el contenido solo por la función oficial ya restringida y por su handoff autorizado.

**Etapa 8 — Perfil (reconciliación de contrato preparada, E2E pendiente):** se eliminó del candidato la copia paralela `ig_original_producer_reports` que se había previsto en `fn_lf_profile_input_governance_resolve_v1`. La función **LIVE existente permanece intacta**: conserva el campo `governance_result` en las tres ramas `READY`, `HUMAN_DECISION_REQUIRED` y `BLOCKED`. Ahora ese **único** `governance_result` contiene `ig_consolidated_original_reports` emitido por `fn_input_governance_execute`, sin segunda consulta RAW ni duplicación del documento íntegro. Los estados `INPUT_GOVERNANCE_REQUIRED` y `NOT_REQUIRED` no inventan RUN, archivo ni recepción.

**Ruta de transporte (código LIVE, no recibo de modelo):** `fn_lf_profile_input_governance_resolve_v1` → `lf_profile_execution_input_validate_v1` almacena `input_governance` en `evidence_payload` → `lf_profile_native_bridge_prepare_v1` devuelve `input_governance` en `NATIVE_MODEL_INPUT_READY` → `profile_continuation.ts` retorna el objeto del bridge sin proyección de `input_governance`. Esa secuencia acredita **compatibilidad estructural**, no una entrega exitosa de los datos candidatos, ni lectura/análisis del modelo.

**Gates antes de cierre:** capturar hash del paquete en el recibo de cada etapa sin reserialización destructiva, confirmar arrays/cantidad de familias y grafos, tamaños máximos/latencias reales, privacidad/PII y la recepción efectiva de `ig_consolidated_original_reports` por el modelo con evidencia específica de RUN. El informe no debe convertirse en un resumen, un `retrieval_handle` o un simple hash. Mantener `model_has_read_report=false` hasta que exista recibo verificable.

## Estados del readback

- `ORIGINALS_CAPTURED`: R1, R2–R6 y G1 originales presentes en el envelope; no es PASS semántico.
- `ORIGINALS_NOT_EMITTED_FOR_REBIND`: Curator creó RUN con evidencia propia, pero no generó diagnósticos nuevos. No implica pérdida de evidencia ni autoriza copiar los del RUN anterior.
- `PARTIAL_ORIGINALS_NOT_EMITTED`: Curator emitió solo parte del paquete de R1/R2–R6/G1; registrar el componente ausente con `producer_emission`.
- `NOT_CAPTURED_LEGACY_RUN`: hubo ejecución histórica sin copia persistida; no re-ejecutar.
- `RUN_STALE` / `RUN_NOT_CURRENT`: el RUN perdió vigencia o carece de atestación de currentness; no usar el RAW.
- `PINNED_AFTER_CURATOR_CAPTURE`: el hash de fuentes se fijó luego de registrar el envelope, pero se verifica identidad estable de RUN/universo y hash original.
- `IG_ORIGINAL_REPORT_INTEGRITY_DRIFT`: alteración de hash, pantalla, Curator, universo o snapshot previamente sellado; bloquear.

`raw_reused=true`, `research_reexecuted=false`, `model_has_read_report=false` son indicadores distintos: transportarlo no prueba que el modelo lo leyó. **No cerrar el reporte final del Perfil con afirmaciones de revisión completa hasta comprobar el consumo del RAW y su recepción.**

## Cobertura sin pérdida / no inferir

1. El RAW almacenado es igual al objeto exacto retornado por Curator y contiene sus JSON anidados tal como fueron emitidos.
2. Nadie debe construir un informe “original” invocando de nuevo un detector o reconstruyendo datos actuales.
3. Un G1 que solo tenía índice antes del cambio no puede recuperarse retroactivamente como RAW antiguo.
4. Una fuente NO emitida debe figurar explícitamente como ausente; no rellenar con texto del LLM.
5. No inventar independencia del Validator; el juez semántico permanece separado y `NOT_TESTED`.
6. No añadir secretos de transporte; aplicar evaluación de volumen, privacidad y tiempo en casos reales antes del merge.

## Pruebas pendientes antes de integrar

- Prueba SQL en transacción de un RUN nuevo y gobernado, sin contaminar históricos.
- Identidad SHA: RAW capturado y RAW transportado *exactamente iguales*.
- Modo `NOOP`: sin nuevo Curator ni R1–R6.
- R2–R6 no emitidos: retorno explícito sin reejecución.
- G1 con más de ocho reglas efectivas elegibles: capturar **todas**, verificar que el conteo de grafos coincide con la selección canónica y conservar su SHA original, sin máximo fijo.
- G1 ya no depende de R6 para escoger raíces. R1–R6 mantienen sus diagnósticos originales; **todavía falta** verificar qué consumidores pueden aprovechar directamente G1 sin repetir trabajo.
- Los 212 `DERIVED_GLOBAL` no pueden tratarse automáticamente como reglas aplicables: registrar su existencia y abrir investigación de aplicabilidad con fuente/autoridad, sin promoverlas ni descartarlas.
- Medir memoria, tiempos y tamaño del JSON en 8, 9, 20 y 71 reglas efectivas elegibles; si existe problema real, justificar paginación íntegra, sin descartar raíces.
- Detectar `raw_graph.graph_limit_hit=true` por regla y reportar los grafos internos truncados. No confundir 'todas las raíces' con 'todas las referencias exploradas'.
- Perfil: inspeccionar `input_validate`, `NATIVE_MODEL_INPUT_READY` y payload realmente recibido, sin pérdida de JSON ni caracteres/arrays.
- Integridad de ACL (SEC-011), fuente vigente (GOV-010), calidad semántica separada (GOV-032) y regresiones de EKB.

**Compatibilidad:** PR #3693 cambia el paquete semántico por familia; este PR preserva informes existentes, sin crear un componente que compita con Curator/Validator.
