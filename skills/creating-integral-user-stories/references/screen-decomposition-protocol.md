# Protocolo normativo de descomposición de pantallas

Versión operativa: `v0.5`. Juez asociado: `J02_SCREEN_DECOMPOSITION`.
Validador: `scripts/validate_screen_decomposition.py`.

## 1. Propósito

Convertir una pantalla y su fuente operativa en inventarios completos, unidades funcionales atómicas y una matriz de cobertura verificable, sin redactar aún Story Packs.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `source_snapshot` | Contenido íntegro, versión, SHA-256 y referencia resoluble. |
| `screen_identity` | screen_code, module_code, estado y responsabilidad principal. |
| `context_inventory` | Contextos visuales y operativos presentes en la fuente. |
| `permission_inventory` | Perfiles, permisos y restricciones por acción. |
| `transition_inventory` | Estados, transiciones permitidas y prohibidas. |
| `related_screens` | Pantallas origen, destino o dependientes. |
| `pending_decisions` | Definiciones abiertas que no pueden inferirse. |

## 3. Preflight

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que J01 terminó en `PASS_WITH_EVIDENCE`.
4. Confirmar que el alcance de lectura y escritura está autorizado.
5. Confirmar independencia worker–juez.
6. Registrar contradicciones o datos ausentes antes de producir contenido.
7. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Validar snapshot, SHA-256 y presencia del `screen_code` objetivo.
2. Construir inventario literal de contextos, campos, acciones, mensajes, permisos, estados, transiciones y dependencias.
3. Asignar un identificador estable a cada elemento fuente y conservar su `source_ref`.
4. Definir la responsabilidad principal en una oración observable.
5. Agrupar por contexto funcional, no por posición visual.
6. Proponer unidades con actor, objetivo, disparador, resultado observable, recurso afectado y riesgo.
7. Separar cuando cambia actor, permiso, resultado, estado, riesgo o recurso persistido.
8. Clasificar cada unidad con una decisión permitida y evidencia.
9. Detectar duplicados semánticos y relaciones con otras pantallas.
10. Construir cobertura uno-a-uno y justificar exclusiones.
11. Recalcular conteos desde los objetos; no confiar en resúmenes declarados.
12. Registrar vacíos como `PENDING_DECISION` o `BLOCKED`; nunca convertirlos en hechos.
13. Validar contra `schemas/screen-decomposition.schema.json`.
14. Ejecutar `scripts/validate_screen_decomposition.py`.
15. Entregar a J02 sin autoaprobación.

## 5. Reglas e invariantes

- Una pantalla no equivale a una historia y un paso visual no equivale a una unidad funcional.
- Responsive, accesibilidad, analytics, logs, auditoría, tokens y manejo genérico de errores son transversales salvo capacidad independiente.
- Una unidad `CREATE_STORY` debe tener resultado aceptable de forma independiente.
- `MERGE_WITH` requiere `merge_target` existente y razón de inseparabilidad.
- `CONFIRMED` requiere `source_ref`; `INFERRED` y `PROPOSED` conservan su etiqueta.
- Ninguna unidad puede quedar sin actor, objetivo, resultado observable o justificación.
- `coverage_summary` debe coincidir con los objetos recalculados.

## 6. Contrato de salida

Salida principal: `schemas/screen-decomposition.schema.json` y envelope `schemas/judge-result.schema.json` v0.5.

La salida incluye referencias, conteos, assertions actual/expected, decisiones pendientes, hashes y rutas de evidencia. Una salida válida por forma pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
source_snapshot_sha_present = 0
source_screen_code_matches_target = 0
context_coverage = 0
permission_coverage = 0
transition_coverage = 0
unmapped_count = 0
unjustified_count = 0
conflicting_count = 0
duplicate_functional_units = 0
functional_units_complete = 0
confirmed_rules_have_source = 0
coverage_summary_mismatch = 0
```

## 8. Condiciones de bloqueo

```text
source_screen_not_found = true
operational_source_unavailable = true
source_version_conflict = true
required_decision_prevents_decomposition = true
semantic_validator_unavailable = true
```

## 9. Casos de control

### Positivo

Todos los elementos fuente están `MAPPED` o `JUSTIFIED_OUT`, no hay duplicados, las unidades están completas, schema y runtime pasan.

### Negativo

Un elemento `PENDING`, una unidad duplicada, `MERGE_WITH` sin `merge_target` o un resumen con `unmapped_count > 0` debe ser rechazado.

## 10. Reparación

Reparar exclusivamente el objeto asociado; no reducir umbrales, borrar assertions ni modificar la fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con evidencia acumulada.

## 11. Handoff

Entregar versión, hashes, inventarios, unidades, cobertura recalculada, assertions, fallas, decisiones pendientes, reparaciones y `evidence_refs` resolubles.

## 12. Benchmark dual verificado

Fecha: `2026-07-30`.

- **Claude Skills — anthropics/skills:** `skills/skill-creator/SKILL.md`; procedimiento determinista, progressive disclosure, evals y reparación iterativa.
- **freeCodeCamp/freeCodeCamp:** `curriculum/schema/challenge-schema.js`; constraints condicionales, unicidad y rechazo determinista.
- **Significant-Gravitas/AutoGPT:** `classic/original_autogpt/CLAUDE.md`; estado reproducible, orden de componentes y límites operativos.

**Hallazgo diferencial incorporado:** la cobertura se recalcula desde objetos y se compara con el resumen, evitando PASS por conteos autorreportados.

Los contratos LF prevalecen ante cualquier diferencia.
