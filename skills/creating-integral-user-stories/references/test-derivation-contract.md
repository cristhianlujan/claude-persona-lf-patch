# Contrato de derivación de pruebas

Versión operativa: `v0.4`. Juez asociado: `J10_TEST_COVERAGE`.

## 1. Propósito

Derivar cobertura trazable y determinista de criterios, reglas, permisos, estados, errores, idempotencia, concurrencia, seguridad y calidad transversal, rechazando fixtures genéricos, evidencia vacía y PASS vacuos.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `story_pack` | Story Pack aprobado hasta J09. |
| `acceptance_criteria` | Criterios Given/When/Then con códigos y referencias. |
| `critical_rules` | Validaciones, permisos, tenant, estados, idempotencia, concurrencia y riesgos. |
| `error_catalog` | Errores, estados observables y políticas de reintento. |
| `traceability_matrix` | Referencias resolubles fuente → regla → criterio. |
| `test_environment` | Actores, tenants, estado inicial, datos controlados y restricciones de ejecución. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que J01–J09 aplicables terminaron en `PASS_WITH_EVIDENCE`.
4. Confirmar que el alcance de lectura y escritura está autorizado.
5. Confirmar independencia entre worker y juez.
6. Confirmar disponibilidad del validador semántico dedicado.
7. Registrar contradicciones o datos ausentes antes de producir contenido.
8. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Crear al menos una prueba positiva por criterio de aceptación.
2. Crear pruebas de límites para validaciones críticas.
3. Crear prueba negativa por permiso.
4. Crear prueba cross-tenant por regla multiempresa.
5. Crear prueba por transición permitida y prohibida.
6. Crear prueba de duplicidad para acciones idempotentes.
7. Crear prueba de concurrencia para cada recurso mutable compartido.
8. Crear prueba por error crítico y política de reintento.
9. Crear pruebas de auditoría, analytics sin PII y correlación.
10. Crear pruebas responsive y de accesibilidad aplicables.
11. Asignar a cada prueba un fixture exacto: actor, tenant, estado inicial, entradas, pasos, resultado esperado y `evidence_path`.
12. Asignar `criterion_ref` o `rule_ref` resoluble.
13. Detectar pruebas huérfanas, reglas sin prueba, referencias rotas y resultados no observables.
14. Ejecutar el validador semántico y registrar actual/expected por assertion.
15. Entregar matriz de cobertura y evidencia a J10.

## 5. Reglas e invariantes

- Cada prueba referencia `criterion_ref` o `rule_ref` resoluble.
- `expected_result` debe ser observable y no repetir solo el nombre de la prueba.
- Las pruebas negativas no se sustituyen por una prueba positiva genérica.
- Modificar la historia para hacer pasar una prueba está prohibido.
- Los datos se minimizan y no usan PII real.
- Casos deterministas usan valores controlados y resultados exactos.
- Fixtures con `<placeholder>`, `TODO`, `TBD`, `example` vacío o pasos genéricos son inválidos.
- Pruebas costosas se separan de las rápidas pero permanecen en la cobertura.
- `assertions_passed = assertions_total` y `evidence_refs` no vacío son obligatorios para PASS.
- La ausencia del runtime semántico produce `BLOCKED`, no PASS editorial.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/tests` y `schemas/coverage-report.schema.json`.

Cada prueba debe incluir como mínimo:

```json
{
  "test_code": "TEST-TENANT-001",
  "family": "TENANT",
  "criterion_ref": null,
  "rule_ref": "SEC-CROSS-TENANT-DENY",
  "preconditions": ["actor belongs to COMPANY-A", "record belongs to COMPANY-B"],
  "exact_inputs": {"record_id": "REC-B-001"},
  "initial_state": {"authenticated_tenant": "COMPANY-A"},
  "steps": ["request REC-B-001 through the authorized application path"],
  "expected_result": "access is denied and no record attributes are returned",
  "negative": true,
  "tenant_scope": "CROSS_TENANT",
  "evidence_path": "evidence/tests/TEST-TENANT-001.json"
}
```

La salida debe incluir versión de fuente, hashes, conteos, assertions evaluadas, decisiones pendientes, comando, identidad del ejecutor y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
acceptance_criteria_without_test = 0
critical_rule_without_test = 0
permission_without_negative_test = 0
tenant_rule_without_cross_tenant_test = 0
state_transition_without_state_test = 0
idempotent_action_without_duplicate_test = 0
critical_error_without_test = 0
mutable_shared_resource_without_concurrency_test = 0
tests_without_exact_fixture = 0
tests_without_expected_result = 0
tests_without_traceability_ref = 0
orphan_tests = 0
vacuous_pass_count = 0
```

## 8. Condiciones de bloqueo

```text
story_pack_missing = true
test_derivation_source_missing = true
critical_expected_behavior_undefined = true
dedicated_semantic_validator_available = false
worker_judge_independence_broken = true
input_sha256_missing = true
```

## 9. Casos de control

### Positivo

Una suite completa, con fixtures exactos y todas las assertions en cero, produce `READY_FOR_JUDGE`; J10 puede emitir `PASS_WITH_EVIDENCE` únicamente después de ejecutar el runtime y validar hashes y evidencia.

### Negativo reparable

Una prueba de permiso sin caso DENY, una referencia rota o un fixture genérico produce `RETURN_TO_WORKER` con assertion y ruta exacta.

### Bloqueado

Runtime semántico ausente, fuente faltante, hash ausente o independencia rota produce `BLOCKED` y `compliance_bit=0`.

## 10. Reparación

Cuando una assertion falle, reparar exclusivamente el objeto asociado; no reducir el umbral, borrar la assertion, fabricar una referencia ni modificar la fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con la evidencia acumulada.

## 11. Handoff

Entregar al juez: versión de fuente, SHA-256 de entrada y salida, objetos procesados, conteos, assertions actual/expected, fallas, decisiones pendientes, reparaciones aplicadas, comando, ejecutor y `evidence_refs` resolubles.

## 12. Benchmark dual verificado

Fecha de verificación: `2026-07-29`.

- **Claude Skills — anthropics/skills:** `skills/skill-creator/SKILL.md`, blob `65b3a402dbd09b8e83f9d637c6b553875189085c`; patrones aplicados: casos realistas, assertions objetivas, grading programático, benchmark y reparación iterativa.
- **freeCodeCamp/freeCodeCamp — 453125 estrellas:** `curriculum/schema/challenge-schema.js`, blob `7db60817942625110525fd313bf80f1df067f006`; complemento: validaciones condicionales, unicidad, referencias relativas y mensajes de error deterministas.
- **Significant-Gravitas/AutoGPT — 185741 estrellas:** `classic/original_autogpt/CLAUDE.md`, blob `9c6d04300f83621b00e804298b7b8ea9ce3953c7`; complemento: fixtures aislados, persistencia de estado y límites de ejecución.

**Hallazgo diferencial incorporado:** fixture exacto + detección de PASS vacuo + gate de runtime semántico forman una única cadena verificable.

Los contratos LF y la fuente operativa prevalecen ante cualquier diferencia.
