# Protocolo normativo de descomposición de pantallas

Versión operativa: `v0.3`. Juez asociado: `J02_SCREEN_DECOMPOSITION`.

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

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Validar que el snapshot existe, que su SHA-256 está disponible y que el screen_code objetivo aparece en la fuente.
2. Construir un inventario literal de contextos, campos, acciones, mensajes, permisos, estados, transiciones y dependencias.
3. Asignar un identificador estable a cada elemento fuente y conservar su source_ref.
4. Definir la responsabilidad principal de la pantalla en una sola oración observable.
5. Agrupar elementos por contexto funcional, no por posición visual.
6. Proponer unidades funcionales con actor, objetivo, disparador, resultado observable, recurso afectado y nivel de riesgo.
7. Aplicar la prueba de atomicidad: separar cuando cambia actor, permiso, resultado, estado, riesgo o recurso persistido.
8. Clasificar cada unidad con una decisión permitida y justificarla con evidencia.
9. Detectar duplicados semánticos y relaciones con otras pantallas antes de crear historias.
10. Construir la matriz de cobertura y demostrar que cada elemento fuente está mapeado o justificado.
11. Registrar contradicciones y vacíos como PENDING_DECISION o BLOCKED; nunca convertirlos en hechos.
12. Entregar el resultado a J02 sin autoaprobarlo.

## 5. Reglas e invariantes

- Una pantalla no equivale a una historia y un paso visual no equivale a una unidad funcional.
- Responsive, accesibilidad, analytics, logs, auditoría, tokens y manejo genérico de errores son transversales salvo que entreguen una capacidad independiente a un actor.
- Una unidad CREATE_STORY debe tener un resultado de negocio aceptable de forma independiente.
- MERGE_WITH requiere merge_target existente y razón de inseparabilidad.
- CONFIRMED requiere source_ref resoluble; INFERRED y PROPOSED deben conservar su clasificación.
- Ninguna unidad puede quedar sin actor, objetivo, resultado observable o justificación.

## 6. Contrato de salida

Salida principal: `schemas/screen-decomposition.schema.json`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
source_snapshot_sha_present = true
unmapped_count = 0
unjustified_count = 0
conflicting_count = 0
duplicate_functional_units_count = 0
functional_units_without_actor_count = 0
functional_units_without_goal_count = 0
functional_units_without_output_count = 0
confirmed_rules_without_source_count = 0
```

## 8. Condiciones de bloqueo

```text
source_screen_not_found = true
operational_source_unavailable = true
source_version_conflict = true
required_decision_prevents_decomposition = true
```

## 9. Ejemplo mínimo completo

```json
{
  "functional_unit_code": "FU-CUSTOMER-QUERY-001",
  "actor": "Operador con permiso CUSTOMER_READ",
  "goal": "consultar un cliente por documento",
  "observable_output": "resultado vigente o estado vacío explícito",
  "decision": "CREATE_STORY",
  "justification": "La consulta produce un resultado independiente y no modifica datos.",
  "source_ref": "SRC-SCR-CUSTOMER#actions.search",
  "classification": "CONFIRMED"
}
```

## 10. Reparación

Cuando una assertion falle, reparar exclusivamente el objeto asociado; no reducir el umbral, borrar la assertion ni modificar la fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con la evidencia acumulada.

## 11. Handoff

Entregar al juez: versión de fuente, SHA-256, objetos procesados, conteos, assertions, fallas, decisiones pendientes, reparaciones aplicadas y evidence_refs resolubles.

## 12. Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.
- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.

Estas fuentes aportan patrones de ejecutabilidad, validación y pruebas. Los contratos LF y la fuente operativa prevalecen ante cualquier diferencia.
