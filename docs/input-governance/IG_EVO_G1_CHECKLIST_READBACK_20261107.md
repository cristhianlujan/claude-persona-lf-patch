# IG LF — G1 | Checklist de inventario de grafo

**Fecha:** 2026-11-07 · **Estado:** auditoría estática de función LIVE y revisión de corrección candidata #3694. **SIN** ejecutar otra vez G1, SQL de migración, Curator o informes históricos.  
**Fuente oficial LIVE:** `programacion.fn_ig_evo_rule_graph_inventory_v1(p_pantalla_id,p_regla_id,p_max_hops DEFAULT 3)`; MD5 de función `3acbd3d90eb95793ee753495a8950d55`.  
**Caso referencial:** pantalla 51 `B2B-AUTH-001`, obtenido por SELECT de vínculos canónicos: 283 reglas distintas, 71 atestadas como raíces G1 (`binding_source<>'DERIVED_GLOBAL'`, estados `VIGENTE/CANDIDATO`), 212 vínculos `DERIVED_GLOBAL` sin autoridad de raíz específica. Son observaciones, no valores hardcoded.

## Entrada → proceso → salida

```text
Curator materializador existente → selector canónico de raíces G1
   → fn_ig_evo_rule_graph_inventory_v1(screen, rule, 3)
   → raw_graph original por raíz con nodes[], edges[], source context y flags
   → proposal_materialization.ig_evo_graph_index[].raw_graph
   → archivo RAW del envelope del RUN (#3694 candidato NO desplegado)
```

## Checklist

| Control | Estado | Verificación |
|---|---|---|
| Fuente canónica de raíces | **PASS del selector candidato** | `fn_input_effective_rule_links_v1(screen,'INPUT_GOVERNANCE')` + vínculos no `DERIVED_GLOBAL` + `VIGENTE/CANDIDATO`. G1 LIVE exige esta vinculación para aceptar una regla |
| Límite arbitrario de ocho raíces | **ELIMINADO EN CANDIDATO** | Se reemplazó `ORDER BY rule_id LIMIT 8` por todas las raíces G1 admisibles; se compara `count(grafos)=count(raíces)`. No compilado en LIVE |
| El caso de vínculos derivados globales | **PENDIENTE DE ATESTACIÓN DE APLICABILIDAD** | 212 `DERIVED_GLOBAL` no pueden promoverse implícitamente como raíces G1; se registran conteo y referencia de fuente |
| Estado de cada raíz | **PASS de estructura** | G1 valida pantalla, regla, `binding_source`, estado y obtiene hash de fila fuente, contexto de pantalla/módulo, y descripciones originales |
| Referencias transversales/JSON anidado | **PASS de estructura limitado** | Inspecciona hojas numéricas/string con claves de referencia reconocidas dentro de `valor_config`; recorrido recursivo JSON `d<24` |
| Resolución por autoridad | **PASS de separación** | Para políticas, usa identificador y bindings `lf_ops.pantallas_politicas`. Un vínculo encontrado sin binding válido queda como `SOURCE_FOUND_BINDING_NOT_ATTESTED`, no se presume permitido |
| Límite **interno** de exploración | **RIESGO DECLARADO** | `p_max_hops` entre 1 y 5 (por defecto 3), cola de hasta 128 nodos, 512 referencias. Son acotamientos del recorrido **por raíz**, no el antiguo tope global de ocho grafos. Su justificación de capacidad aún no se ha medido |
| Detección de parcialidad | **PASS de lógica declarativa** | `graph_limit_hit` y `graph_reference_status=TRUNCATED` cuando se agota presupuesto. El PR #3694 prepara conteo e IDs de raíces con `graph_limit_hit=true` |
| Inventario de cláusulas e intención | **CONTEXTO, NO SEMÁNTICA** | Incluye texto original `titulo/descripcion/razon/pendiente_detalle`, `narrative_clause_inventory`, `intent_interpretation_request`; `semantic_interpretation_performed=false`, `semantic_match_status=NOT_TESTED` |
| Integridad y reutilización | **CANDIDATO / NO SQL E2E** | El PR guarda `raw_graph=g.doc` desde el mismo cálculo, sin volver a invocar G1 al transportar. No existe recibo de igualdad JSON+SHA de ejecución real |
| QA/seguridad/políticas | **NOT_TESTED** | Inventario de aristas no demuestra seguridad server-side, protección antiabuso, cumplimiento de políticas ni control semántico |

## Estados y reglas de cierre

- **`ALL_G1_ATTESTED_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS`** (candidato): todas las raíces G1 admitidas se inventariaron, sin autorizar conclusión semántica.
- **`ALL_G1_ATTESTED_RULE_ROOTS_CAPTURED_WITH_INTERNAL_TRUNCATION`** (candidato): se capturaron las raíces, pero alguna exploración interna llegó al tope. Debe reportarse IDs afectados y evidencia parcial.
- **`UNATTESTED_SCREEN_APPLICABILITY_NOT_G1_ROOT_ELIGIBLE`** (candidato): quedan vínculos `DERIVED_GLOBAL` que necesitan autoridad de pantalla, sin afirmación de que G1 los procesó.
- **`NOT_TESTED`** para correspondencia semántica entre cláusulas textuales, políticas y relaciones.

**Decisión:** el código candidato G1 tiene cobertura de todas las raíces atestadas y no recorta a ocho. **No se cierra G1 funcionalmente** sin probar ejecución del candidato en entorno gobernado, exactitud de hashes, volumetría y casos de truncamiento. Sin repetir cálculos históricos.

**Siguiente lote en orden:** Validator → consolidación de Input Governance → Perfil al final. Evaluar independencia, recibos y estados por familia; jamás aceptar `PASS` como sinónimo de QA o runtime.  
**EKB:** GOV-010, GOV-032, SEC-011, IG-M107-A3, IG-M46.
