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
| G1 | `fn_ig_evo_rule_graph_inventory_v1` | `proposal_materialization.ig_evo_graph_index[].raw_graph`: salida entera de **cada grafo efectivamente calculado** y copiado del mismo valor `g.doc`, no un segundo escaneo |
| Validator | `input_family_assessments.validator_*` y recibo Curator→Validator existente | No se modifica su proceso; se conserva evidencia y dictamen por el mecanismo ya vigente. Aún no se certificó un RAW de Validator de extremo a extremo |

**Importante:** se elimina el límite arbitrario de 8 raíces. El índice calcula **todas las raíces distintas descubiertas por R6** (sin `LIMIT` fijo), y conserva cada `g.doc` original en el mismo cómputo. Se valida que `graph_captured_root_count = graph_discovered_root_count`; una diferencia bloquea y no se oculta. **Esto cubre todas las raíces R6 identificadas, no necesariamente todas las reglas de la pantalla.** No se re-investigan raíces ya calculadas. Si el volumen/latencia resulta problemático, deberá medirse y justificarse una estrategia de transporte por lotes, sin imponer un nuevo máximo silencioso.

## Captura una sola vez por RUN

- En la respuesta final `v_full_original_response` del mismo Curator, persistir `programacion.input_governance_producer_raw_v1.original_curator_output` y su SHA-256 calculado sobre **los mismos bytes semánticos JSONB** (sin normalizar a sinopsis).
- `run_id` es PK; no sobrescribir el RAW anterior ni mezclar RUN. Registrar pantalla, identidad del Curator y `source_snapshot_sha256`.
- Solo se inserta para `BOOTSTRAP`, `REBIND`, `SOURCE_STALE_RECURATE` y `FULL_RECURATE`. `NOOP` **reutiliza** el informe previamente guardado; no lo recalcula.
- Para `REBIND`, cuando las funciones R1–R6 no fueron invocadas, devolver `PARTIAL_ORIGINALS_NOT_EMITTED`, jamás inventar sus resultados ni interpretar N/A sin autoridad.
- Los RUN anteriores a esta migración devuelven `NOT_CAPTURED_LEGACY_RUN`; **no ejecutar de nuevo R1 ni Curator para rellenarlos**.

## Transporte por el camino existente

```text
Curator original (incluye R1, R2–R6 y G1 ya calculados)
  └─ almacén inmutable, mismo run_id, hash del envelope
     └─ lectura autorizada por programacion.fn_input_governance_producer_raw_read_v1
        └─ fn_lf_profile_input_governance_resolve_v1
           └─ input_governance.ig_original_producer_reports
              └─ input_validate → lf_profile_native_bridge_prepare_v1
                 └─ perfil recibe el contenido completo, no una proyección
```

La función lectora es interna (`SECURITY DEFINER`, sin `EXECUTE` para PUBLIC, anon, authenticated ni service_role). El perfil obtiene el contenido solo por la función oficial ya restringida y por su handoff autorizado.

El mensaje al Perfil contiene **dos cosas complementarias**: el `context_manifest` para navegación y `ig_original_producer_reports.original_curator_output` íntegro para su análisis. La segunda no es simplemente `retrieval_handles`, `hashes`, `summary` ni `ig_evo_graph_index` abreviado.

## Estados del readback

- `ORIGINALS_CAPTURED`: R1 + R2–R6 originales presentes en el envelope; no es PASS semántico.
- `PARTIAL_ORIGINALS_NOT_EMITTED`: el Curator produjo un envelope, pero no emitió los dos grupos de R*.
- `NOT_CAPTURED_LEGACY_RUN`: hubo ejecución histórica sin copia persistida; no re-ejecutar.
- `RUN_STALE`: el RUN perdió vigencia; no usar el RAW.
- `IG_ORIGINAL_REPORT_INTEGRITY_DRIFT`: hash, pantalla, Curator o snapshot difiere; bloquear.

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
- G1 con más de ocho raíces descubiertas: capturar **todas**; comprobar identidad de hashes y conteo exacto, sin truncar por cardinalidad.
- G1 con alcance parcial de R6 frente al universo total de reglas: reportar su alcance real, sin simular cobertura del universo.
- Medir memoria, tiempos y tamaño del JSON en escenarios de 8, 9 y 20+ raíces; si surge un problema, documentar causa técnica y diseñar paginación íntegra, nunca descartar raíces.
- Perfil: inspeccionar `input_validate`, `NATIVE_MODEL_INPUT_READY` y payload realmente recibido, sin pérdida de JSON ni caracteres/arrays.
- Integridad de ACL (SEC-011), fuente vigente (GOV-010), calidad semántica separada (GOV-032) y regresiones de EKB.

**Compatibilidad:** PR #3693 cambia el paquete semántico por familia; este PR preserva informes existentes, sin crear un componente que compita con Curator/Validator.
