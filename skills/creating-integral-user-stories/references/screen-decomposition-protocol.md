# Protocolo normativo de descomposición de pantallas

Versión operativa: `v0.6`. Juez independiente asociado: `J02_SCREEN_DECOMPOSITION v0.8`.

## 1. Propósito

Convertir una pantalla y su fuente operativa en un objeto `screen_decomposition` completo, trazable y conforme a `schemas/screen-decomposition.schema.json`, sin redactar Story Packs ni ejecutar el juez desde el worker.

La identidad del worker no es fija: el orquestador la resuelve y la fija en `task_packet.worker_binding`. Un `worker_profile` puede existir como compatibilidad, pero no es autoridad de selección.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `task_packet.worker_binding` | Worker resuelto, autoridad/revisión/digest, ejecución de orquestador, dispatch receipt y `ORCHESTRATOR_ENTRY_ACCEPTED`. |
| `source_snapshot` | Contenido íntegro, versión, SHA-256 y referencia resoluble. |
| `screen_identity` | `screen_code`, `module_code`, estado y responsabilidad principal. |
| `context_inventory` | Contextos visuales y operativos con `code`, descripción y `source_ref`. |
| `field_inventory` | Campos visibles, editables, calculados y sensibles con `code`, `context_code` y `source_ref`. |
| `visual_observation_inventory` | Evidencia visual v0.2 bloqueada, preservada 1:1 cuando aplique. |
| `permission_inventory` | Perfiles, permisos y restricciones por acción con `permission_code` y `source_ref`. |
| `transition_inventory` | Estados, acciones, transiciones permitidas/prohibidas y `source_ref`. |
| `related_screens` | Pantallas origen, destino o dependientes. |
| `pending_decisions` | Definiciones abiertas que no pueden inferirse, con `blocking` y `status`. |
| `previous_judge_result` | J01 debe ser `PASS_WITH_EVIDENCE`. |

## 3. Preflight obligatorio

1. Validar `task_packet` v0.4 y `worker_binding.resolution_mode=ORCHESTRATOR_RESOLVED`.
2. Exigir `entry_guard_code=ORCHESTRATOR_EXECUTION_GUARD_V1` y `entry_guard_decision=ORCHESTRATOR_ENTRY_ACCEPTED`.
3. Confirmar que todas las entradas pertenecen a la misma versión de fuente.
4. Resolver referencias, SHA-256, `screen_code`, versión y responsabilidad principal.
5. Confirmar que J01 terminó en `PASS_WITH_EVIDENCE`.
6. Confirmar alcance autorizado de lectura y escritura.
7. Confirmar independencia worker–juez: el worker no ejecuta ni sustituye a J02.
8. Confirmar disponibilidad del schema, contrato J02 y runtime semántico.
9. Reconciliar el SHA del runtime con el source actual y el registro declarado por J02. En `CANDIDATE_CI_ONLY`, el URI `candidate://...` exacto habilita solo evaluación del candidato; una promoción exige registro canónico en Supabase.
10. Bloquear antes de assertions semánticas cuando falte identidad del ejecutor, versión del juez, inputs, inventarios, unidades, cobertura, schema, runtime, registro o SHA reconciliable.
11. Detener con `BLOCKED` cuando exista una decisión `blocking=true` y `status=OPEN`.

## 4. Procedimiento obligatorio

1. Validar snapshot, SHA-256 y presencia del `screen_code` objetivo.
2. Construir inventarios literales de contextos, campos, permisos y transiciones.
3. Asignar identificador estable y `source_ref` a cada elemento fuente.
4. Definir la responsabilidad principal en una oración observable.
5. Proponer unidades funcionales por resultado de negocio, no por posición visual.
6. Separar cuando cambie actor, permiso, resultado, estado, riesgo o recurso persistido.
7. Completar actor, objetivo, trigger, resultado observable, riesgo, decisión, justificación, clasificación y fuente de cada unidad.
8. Exigir `merge_target` cuando la decisión sea `MERGE_WITH`.
9. Detectar duplicados por código y por equivalencia semántica de actor, objetivo y resultado observable.
10. Construir `coverage_items` uno-a-uno para cada contexto, campo, permiso y transición.
11. Usar `source_type` exacto: `CONTEXT`, `FIELD`, `PERMISSION` o `TRANSITION`.
12. Mapear `MAPPED` solo a unidades funcionales declaradas; justificar `JUSTIFIED_OUT` con evidencia.
13. Para `screen-ingestion/v0.2`, preservar `visual_observation_inventory` 1:1 por `(observation_code, source_ref)`.
14. No promover a `CONFIRMED` una unidad cuya fuente visual sea `INFERRED`, `NOT_OBSERVABLE`, contradictoria o tenga incertidumbre abierta.
15. Registrar conflictos o pendientes sin convertirlos en hechos.
16. Recalcular `coverage_summary` desde `coverage_items`; no confiar en conteos autorreportados.
17. Validar el objeto completo contra `schemas/screen-decomposition.schema.json`.
18. Emitir evidencia y handoff al juez independiente.
19. J02 v0.8 ejecuta `scripts/validate_screen_decomposition_visual.py`; el worker nunca ejecuta su propio juez.

`coverage_items` forma parte de `screen_decomposition`. No existe una salida paralela llamada `coverage_matrix`.

## 5. Invariantes

- Una pantalla no equivale a una historia y un paso visual no equivale a una unidad funcional.
- Responsive, accesibilidad, analytics, logs, auditoría, tokens y manejo genérico de errores son transversales salvo capacidad independiente.
- Una unidad `CREATE_STORY` debe producir un resultado aceptable de forma independiente.
- `MERGE_WITH` requiere `merge_target` existente y razón de inseparabilidad.
- `CONFIRMED` requiere `source_ref` resoluble y evidencia epistémicamente compatible; `INFERRED` y `PROPOSED` conservan su etiqueta.
- Ninguna unidad puede quedar sin código, actor, objetivo, trigger, resultado observable, riesgo, decisión, justificación, clasificación o fuente.
- Cada elemento de `context_inventory`, `field_inventory`, `permission_inventory` y `transition_inventory` debe estar cubierto por código o `source_ref` verificable.
- Toda observación visual v0.2 debe conservarse downstream; preservarla no obliga a convertirla en unidad funcional.
- `coverage_summary` debe coincidir exactamente con los objetos recalculados.
- Ningún `coverage_item` puede apuntar a una unidad funcional desconocida.
- Una decisión bloqueante o incertidumbre crítica abierta impide PASS.
- Ningún worker puede autoasignarse ni sobrescribir el binding del orquestador.

## 6. Contrato de salida

La salida principal es un objeto `screen_decomposition` conforme a `schemas/screen-decomposition.schema.json` y contiene:

- `screen_code`, `module_code`, `source_version`, `source_snapshot_sha`, `main_responsibility`;
- `context_inventory`, `field_inventory`, `permission_inventory`, `transition_inventory`;
- `functional_units`, `coverage_items`, `coverage_summary`, `pending_decisions`;
- `visual_observation_inventory` cuando la ingesta sea v0.2.

La evidencia para J02 incluye schema, hashes, inventarios, conteos, cobertura recalculada, duplicados, assertions, reparaciones, identidad independiente, versión del juez, comando y referencias resolubles.

## 7. Assertions J02 v0.8 — 26/26

El runtime efectivo es `validate_screen_decomposition_visual.py`: hereda 23 assertions de `validate_screen_decomposition_v08.py` y agrega 3 assertions visuales/epistémicas. El universo vigente es exactamente:

```text
input_schema_valid = 0
ingestion_schema_valid = 0
source_snapshot_sha_present = 0
source_screen_code_matches_target = 0
ingestion_screen_code_matches_target = 0
ingestion_source_snapshot_hash_matches = 0
ingestion_locked = 0
inventory_complete_vs_ingestion = 0
context_coverage = 0
field_coverage = 0
permission_coverage = 0
transition_coverage = 0
unmapped_count = 0
unjustified_count = 0
conflicting_count = 0
duplicate_functional_units = 0
functional_units_complete = 0
functional_units_without_code = 0
coverage_mapped_to_unknown_functional_unit = 0
confirmed_rules_have_source = 0
coverage_summary_mismatch = 0
blocking_pending_decisions = 0
blocking_ingestion_uncertainty = 0
visual_observation_coverage = 0
confirmed_epistemic_invariants = 0
confirmed_inherited_inference = 0
```

No se permite usar el histórico 17/17 ni el base 23/23 como sustituto del wrapper vigente 26/26.

## 8. Condiciones de bloqueo

```text
worker_binding_invalid = true
source_screen_not_found = true
source_version_conflict = true
required_decision_prevents_decomposition = true
input_schema_unavailable = true
semantic_validator_unavailable = true
semantic_validator_unregistered = true
semantic_validator_sha_unreconciled = true
executor_identity_missing = true
judge_version_missing = true
input_sha256_missing = true
required_input_missing = true
inventory_missing_or_invalid = true
functional_units_empty = true
coverage_items_empty = true
source_version_or_main_responsibility_empty = true
critical_ingestion_uncertainty_open = true
```

## 9. Casos de control obligatorios

### Positivo

El wrapper vigente debe producir `PASS_WITH_EVIDENCE`, `assertions_passed = 26`, `assertions_total = 26`, `compliance_bit = 1` y salida válida contra `schemas/judge-result.schema.json`.

### Negativos

Deben rechazarse o bloquearse, según contrato:

1. `MERGE_WITH` sin `merge_target`.
2. Trigger vacío.
3. `coverage_item` pendiente.
4. Unidad duplicada por código.
5. Unidad duplicada por semántica con código distinto.
6. Contexto ajeno cubierto por cardinalidad.
7. Campo sin cobertura `FIELD`.
8. Decisión bloqueante abierta.
9. Runtime ausente.
10. Runtime no registrado o SHA no reconciliado.
11. Mapeo a unidad desconocida.
12. Unidades funcionales vacías.
13. `coverage_items` vacíos.
14. Identidad del ejecutor o versión del juez ausente.
15. Observación visual v0.2 omitida downstream.
16. Unidad `CONFIRMED` sustentada solo por evidencia `INFERRED`/`NOT_OBSERVABLE`.
17. Unidad `CONFIRMED` con incertidumbre de fuente abierta.
18. Binding de worker no resuelto por orquestador.

## 10. Reparación

Reparar exclusivamente el objeto asociado; no reducir umbrales, borrar assertions, debilitar el schema, inventar fuentes, cambiar una decisión bloqueante sin evidencia ni permitir autoaprobación. Tras `retry_limit = 2`, devolver `BLOCKED` con evidencia acumulada.

## 11. Handoff

Entregar binding del worker, versión, hashes, inventarios, unidades, `coverage_items`, evidencia visual preservada, cobertura recalculada, assertions actual/expected, fallas, decisiones pendientes, reparaciones, identidad del ejecutor y `evidence_refs` resolubles.

## 12. Registro y promoción

```text
candidate runtime:
  scripts/validate_screen_decomposition_visual.py
candidate registration:
  candidate://creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION_VISUAL
runtime SHA-256:
  af30bd17d5c2fb91d1d2932b64e762bfc30cd27f963d0cbf215417c6dc95e7c2
runtime Git blob:
  63bd13fc5158528c777ede56e2f2ad09d0827669
promotion registration:
  PENDING_CANONICAL_SUPABASE_REGISTRATION
```

Un `candidate://` permite evaluar el candidato, no declarar que Supabase ya lo promovió. Hasta que el registro canónico sea aplicado y leído de vuelta, el estado sigue `CANDIDATE_CI_ONLY`.

## 13. Benchmark dual verificado

Fecha: `2026-07-29`.

- **Claude Skills — anthropics/skills:** `skills/skill-creator/SKILL.md`, blob `65b3a402dbd09b8e83f9d637c6b553875189085c`; procedimiento determinista, progressive disclosure, evals y reparación iterativa.
- **freeCodeCamp/freeCodeCamp:** `curriculum/schema/challenge-schema.js`, blob `7db60817942625110525fd313bf80f1df067f006`; constraints condicionales, unicidad y rechazo determinista.

Los contratos LF prevalecen ante cualquier diferencia.
