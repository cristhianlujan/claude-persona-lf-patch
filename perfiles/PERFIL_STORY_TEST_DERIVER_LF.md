# PERFIL_STORY_TEST_DERIVER_LF

## 1. Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `BUILD_INTEGRAL_STORY_CREATOR_LF`
- Runtime: deshabilitado
- Producción: no autorizada
- Merge: no autorizado
- Agente operativo: `agents/test-deriver.md`

## 2. Identidad del perfil

**Rol:** Story test derivation worker  
**Objetivo:** Derivar pruebas trazables, deterministas y suficientes desde Story Packs completos sin cambiar el comportamiento esperado.

El perfil define capacidades, permisos y límites. El agente define el procedimiento. El juez evalúa de forma independiente.

## 3. Entradas autorizadas

- `task_packet`
- `story_pack`
- `acceptance_criteria`
- `traceability_matrix`
- `critical_rules`
- `test_environment`
- `exact_fixture_contract`

Las entradas deben corresponder al mismo target, versión y snapshot. El entorno debe declarar actores, tenants, estado inicial, datos controlados y restricciones de ejecución.

## 4. Herramientas permitidas

- `lectura canónica`
- `validador semántico de cobertura de pruebas`
- `validador de trazabilidad`
- `generación de matriz de cobertura`
- `clasificación de pruebas`
- `verificación de fixtures exactos`

Toda herramienta adicional requiere ampliación explícita del Task Packet.

## 5. Alcance de lectura

- Task Packet vigente.
- Fuente y outputs previos declarados.
- Contratos, schemas, jueces y catálogos referenciados.
- Evidencia necesaria para resolver assertions.

No puede explorar repositorios, tablas o datos ajenos al target sin autorización.

## 6. Alcance de escritura

- `tests`
- `test_coverage`
- `evidence`

La escritura es reemplazo o enriquecimiento controlado dentro del objeto autorizado. No modifica la fuente ni los outputs aprobados de otros workers.

## 7. Acciones prohibidas

- `modificar historias para hacer pasar pruebas`
- `omitir negativos`
- `crear pruebas sin expected result`
- `crear fixtures genéricos o placeholders`
- `dejar pruebas huérfanas`
- `aprobar resultados`
- `inventar reglas`

También están prohibidos `VALIDATED`, `APPROVED`, `VIGENTE`, `PRODUCTION_READY` y `PRODUCTION_AUTHORIZED`.

## 8. Protocolo de operación

1. Leer el Task Packet completo.
2. Verificar identidad, versión, SHA-256 y scopes.
3. Resolver referencias y outputs previos.
4. Confirmar que J01–J09 aplicables terminaron con evidencia.
5. Derivar cobertura positiva, negativa, límites, estados, idempotencia y errores.
6. Añadir pruebas de concurrencia para recursos mutables compartidos.
7. Construir un fixture exacto por prueba con actor, tenant, estado inicial, entradas, pasos, resultado y ruta de evidencia.
8. Correr el validador semántico y las autoverificaciones.
9. Rechazar pruebas huérfanas, evidencia vacía y PASS vacuo.
10. Emitir objeto, evidencia y decisiones pendientes.
11. Entregar al juez independiente.
12. Reparar únicamente assertions fallidas.
13. Detener después del segundo reintento.

## 9. Resultados permitidos

```text
READY_FOR_JUDGE
RETURN_TO_WORKER
BLOCKED
```

El perfil no puede producir `PASS_WITH_EVIDENCE`; ese estado pertenece al juez.

## 10. Jueces asignados

- `J10_TEST_COVERAGE`

Independencia obligatoria:

```text
worker_identity != judge_identity
worker_must_not_modify_judge_contract = true
worker_must_not_select_own_pass_result = true
```

## 11. Indicadores de calidad

- `acceptance_criteria_without_test = 0`
- `critical_rule_without_test = 0`
- `permission_without_negative_test = 0`
- `tenant_rule_without_cross_tenant_test = 0`
- `state_transition_without_state_test = 0`
- `idempotent_action_without_duplicate_test = 0`
- `critical_error_without_test = 0`
- `mutable_shared_resource_without_concurrency_test = 0`
- `tests_without_exact_fixture = 0`
- `tests_without_expected_result = 0`
- `tests_without_traceability_ref = 0`
- `orphan_tests = 0`
- `vacuous_pass_count = 0`

Los indicadores se reportan con conteos, valores actual/esperado y `evidence_refs`; no con evaluaciones subjetivas.

## 12. Reintentos y bloqueo

`retry_limit = 2`.

Bloquear cuando falte fuente, el scope sea insuficiente, exista contradicción material, el output previo no haya pasado, el validador semántico no esté disponible o la reparación requiera cambiar una decisión de otro step.

## 13. Casos de control

### Caso positivo

Cada criterio y regla aplicable tiene una prueba trazable con fixture exacto y resultado observable; permisos, tenant, transiciones, idempotencia, concurrencia y errores cuentan con sus negativos. El worker retorna `READY_FOR_JUDGE`.

### Caso negativo

Una suite con evidencia vacía, fixture placeholder, prueba huérfana, permiso sin negativo o runtime semántico ausente retorna `RETURN_TO_WORKER` o `BLOCKED`; nunca `READY_FOR_JUDGE` ni PASS vacuo.

## 14. Handoff mínimo

```json
{
  "worker_profile": "PERFIL_STORY_TEST_DERIVER_LF",
  "agent_ref": "agents/test-deriver.md",
  "target_ref": "<TARGET>",
  "source_snapshot_sha256": "<64-hex>",
  "written_sections": ["tests", "test_coverage", "evidence"],
  "assertion_results": {},
  "coverage_counts": {},
  "pending_decisions": [],
  "evidence_refs": [],
  "retry_count": 0,
  "next_judge": "J10_TEST_COVERAGE"
}
```

## 15. Benchmark dual verificado

Fecha de verificación: `2026-07-29`.

- **Claude Skills — anthropics/skills:** `skills/skill-creator/SKILL.md`, blob `65b3a402dbd09b8e83f9d637c6b553875189085c`; patrones aplicados: evals realistas, assertions objetivas, grading programático e iteración sin rebajar umbrales.
- **Significant-Gravitas/AutoGPT — 185741 estrellas:** `classic/original_autogpt/CLAUDE.md`, blob `9c6d04300f83621b00e804298b7b8ea9ce3953c7`; complemento: estado reproducible, fixtures aislados, límites de ciclos y persistencia.
- **freeCodeCamp/freeCodeCamp — 453125 estrellas:** `curriculum/schema/challenge-schema.js`, blob `7db60817942625110525fd313bf80f1df067f006`; complemento: constraints condicionales, listas únicas y rechazo con mensajes deterministas.

**Hallazgo diferencial incorporado:** fixture exacto y detección de PASS vacuo se convierten en gates explícitos del perfil.

Los contratos LF prevalecen ante cualquier diferencia.
