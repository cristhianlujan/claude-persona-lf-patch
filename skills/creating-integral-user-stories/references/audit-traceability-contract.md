# Contrato de auditoría y trazabilidad

Versión operativa: `v0.3`. Juez asociado: `J07_AUDIT_TRACEABILITY`.

## 1. Propósito

Mantener una cadena verificable desde la fuente hasta cada regla, criterio, prueba, mutación y evidencia.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `source_snapshot` | Fuente y hash de origen. |
| `story_pack` | Reglas, criterios, campos, pruebas y acciones. |
| `audit_policy` | Eventos y tratamiento de valores sensibles. |
| `traceability_matrix` | Relaciones fuente-regla-criterio-prueba-evidencia. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Enumerar mutaciones, descargas sensibles y cambios de estado.
2. Definir un audit_event_code por acción auditable.
3. Asignar actor, perfil, empresa, recurso, permiso y policy_version.
4. Definir estrategias de previous_state y new_state.
5. Incluir correlation_id e idempotency_key cuando correspondan.
6. Construir enlaces desde source_ref a regla.
7. Enlazar regla con criterion_code.
8. Enlazar criterio o regla con test_code.
9. Enlazar prueba con evidence_path.
10. Detectar roturas, huérfanos y referencias no resolubles.

## 5. Reglas e invariantes

- Toda mutación y descarga sensible genera auditoría.
- Evento sin actor, empresa, recurso o resultado es inválido.
- Auditoría no se sustituye por analytics o logs.
- Valores sensibles usan MASKED, HASH u OMITTED salvo contrato explícito.
- Cada criterio tiene al menos una prueba o una razón de no aplicabilidad aprobada.
- Cada test_code apunta a criterion_ref o rule_ref existente.
- Las referencias deben ser resolubles y versionadas.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/audit y matriz de trazabilidad`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
mutations_without_audit_event = 0
sensitive_downloads_without_audit = 0
editable_fields_without_change_strategy = 0
rules_without_source_reference = 0
criteria_without_test_reference = 0
tests_without_story_reference = 0
traceability_breaks = 0
```

## 8. Condiciones de bloqueo

```text
traceability_matrix_missing = true
source_reference_unresolvable = true
```

## 9. Ejemplo mínimo completo

```text
SRC-001#rule-7
 -> VAL-EMAIL-UNIQUE
 -> AC-003
 -> TEST-VALIDATION-003
 -> evidence/tests/TEST-VALIDATION-003.json
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

## 13. Autoridad independiente de fuente — FRT V1

Para una ejecución operacional J07, el universo que se audita no puede derivarse del mismo Story Pack que se está juzgando. El caller debe entregar un sidecar `lf-source-authority/v1` externo al candidate y fijar su SHA-256 antes de ejecutar el judge.

Contrato mínimo:

```text
source_authority.schema_version = lf-source-authority/v1
source_authority.objects[] = inventario independiente de campos/reglas/errores/permisos/estados/transiciones/evidencia
source_authority.assertions[] = restricciones semánticas fuente -> candidate
source_authority.conflicts[] = contradicciones que no pueden resolverse silenciosamente
```

J07 debe fallar cerrado cuando ocurra cualquiera de estos casos:

- una `source_ref` del candidate no resuelve en el sidecar;
- un objeto fuente obligatorio desaparece de las superficies requeridas del Story Pack;
- la cobertura se calcula contra un universo derivado del candidate;
- requiredness, condición, dependencia, estado, transición, permiso efectivo, idempotencia, límite, locale o frontera temporal contradicen una assertion fuente;
- existe un conflicto fuente abierto y el Story Pack no lo declara;
- el SHA observado del sidecar difiere del SHA fijado por el caller.

Normalización de texto no autoriza pérdida global de significado. NFC, smart quotes y whitespace pueden normalizarse si la policy de comparación lo permite; cambios lexicales materiales, autocompletado de texto truncado o elevación de evidencia requieren soporte fuente adicional.

El modo sin `--require-source-authority` existe únicamente para regresiones históricas de compatibilidad. No es el contrato operacional para generación o cierre funcional.
