# Contrato de derivación de pruebas

Versión operativa: `v0.3`. Juez asociado: `J10_TEST_COVERAGE`.

## 1. Propósito

Derivar una cobertura trazable de criterios, reglas, permisos, estados, errores, idempotencia, concurrencia, seguridad y calidad transversal.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `story_pack` | Story Pack aprobado hasta J09. |
| `acceptance_criteria` | Criterios Given/When/Then. |
| `critical_rules` | Validaciones, permisos, estados y riesgos. |
| `error_catalog` | Errores y políticas de reintento. |
| `traceability_matrix` | Referencias a fuente y reglas. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Crear al menos una prueba por criterio de aceptación.
2. Crear pruebas de límites para validaciones críticas.
3. Crear prueba negativa por permiso.
4. Crear prueba cross-tenant por regla multiempresa.
5. Crear prueba por transición permitida y prohibida.
6. Crear prueba de duplicidad para acciones idempotentes.
7. Crear prueba por error crítico y política de reintento.
8. Crear pruebas de auditoría, analytics y observabilidad.
9. Crear pruebas responsive y de accesibilidad aplicables.
10. Asignar evidencia, precondiciones, pasos y resultado esperado.
11. Detectar tests huérfanos y reglas sin prueba.
12. Entregar matriz de cobertura a J10.

## 5. Reglas e invariantes

- Cada prueba referencia criterion_ref o rule_ref resoluble.
- expected_result debe ser observable y no repetir solo el nombre de la prueba.
- Las pruebas negativas no se sustituyen por una prueba positiva genérica.
- Modificar la historia para hacer pasar una prueba está prohibido.
- Los datos de prueba se minimizan y no usan PII real.
- Casos deterministas usan valores controlados y resultados exactos.
- Pruebas costosas se separan de las rápidas pero permanecen en la cobertura.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/tests`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
acceptance_criteria_without_test = 0
critical_rule_without_test = 0
permission_without_negative_test = 0
tenant_rule_without_cross_tenant_test = 0
state_transition_without_state_test = 0
idempotent_action_without_duplicate_test = 0
critical_error_without_test = 0
tests_without_expected_result = 0
```

## 8. Condiciones de bloqueo

```text
story_pack_missing = true
test_derivation_source_missing = true
critical_expected_behavior_undefined = true
```

## 9. Ejemplo mínimo completo

```json
{
  "test_code": "TEST-TENANT-001",
  "family": "TENANT",
  "rule_ref": "SEC-CROSS-TENANT-DENY",
  "preconditions": ["actor belongs to COMPANY-A", "record belongs to COMPANY-B"],
  "steps": ["request the record through the authorized application path"],
  "expected_result": "access is denied and no record attributes are returned",
  "negative": true,
  "tenant_scope": "CROSS_TENANT",
  "evidence_path": "evidence/tests/TEST-TENANT-001.json"
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
