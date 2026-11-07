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

**Cobertura G1 corregida:** la selección de raíces es independiente de R6. El inventario parte de **todas las reglas efectivas elegibles de la pantalla** usando la fuente canónica `programacion.fn_input_effective_rule_links_v1(pantalla_id,'INPUT_GOVERNANCE')`, sin `DERIVED_GLOBAL`, y las reglas en estado `VIGENTE` o `CANDIDATO`. El mismo contrato de elegibilidad ya se aplica dentro de `fn_ig_evo_rule_graph_inventory_v1`. Se eliminan `LIMIT 8` y cualquier tope fijo de raíces: **`graph_captured_root_count = graph_eligible_rule_count`** es obligatorio. Cada `raw_graph` es el mismo `g.doc` calculado una vez, no un nuevo escaneo para transportar.
  
**Ejemplo de readback:** pantalla `B2B-AUTH-001` (id 51): 283 vínculos globales/effectivos registrados; **71 reglas con vínculo elegible explícito** en la consulta canónica (2026-11-07). El número es una observación, no un valor fijo de implementación. G1 sigue teniendo límites internos de exploración por raíz (128 nodos / 512 referencias) y una profundidad máxima de 5; `graph_limit_hit=true` implica contenido incompleto y requiere remediación, sin declarar una evaluación semántica satisfactoria.

**Límites operativos:** no reemplazar ocho por otro máximo numérico sin métricas. Medir tiempo, memoria, privacidad y tamaño de JSON con RUN nuevo y sus 71 reglas; si se requiere partición por transporte, no descartar ninguna raíz ni recalcular las ya generadas.

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
- G1 con más de ocho reglas efectivas elegibles: capturar **todas**, verificar que el conteo de grafos coincide con la selección canónica y conservar su SHA original, sin máximo fijo.
- G1 ya no depende de R6 para escoger raíces. R1–R6 mantienen sus diagnósticos originales; **todavía falta** verificar qué consumidores pueden aprovechar directamente G1 sin repetir trabajo.
- Medir memoria, tiempos y tamaño del JSON en 8, 9, 20 y 71 reglas efectivas elegibles; si existe problema real, justificar paginación íntegra, sin descartar raíces.
- Detectar `raw_graph.graph_limit_hit=true` por regla y reportar los grafos internos truncados. No confundir 'todas las raíces' con 'todas las referencias exploradas'.
- Perfil: inspeccionar `input_validate`, `NATIVE_MODEL_INPUT_READY` y payload realmente recibido, sin pérdida de JSON ni caracteres/arrays.
- Integridad de ACL (SEC-011), fuente vigente (GOV-010), calidad semántica separada (GOV-032) y regresiones de EKB.

**Compatibilidad:** PR #3693 cambia el paquete semántico por familia; este PR preserva informes existentes, sin crear un componente que compita con Curator/Validator.
