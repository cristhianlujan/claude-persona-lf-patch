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
**Objetivo:** Derivar pruebas trazables y suficientes desde Story Packs completos sin cambiar el comportamiento esperado.

El perfil define capacidades, permisos y límites. El agente define el
procedimiento. El juez evalúa de forma independiente.

## 3. Entradas autorizadas

- `task_packet`
- `story_pack`
- `acceptance_criteria`
- `traceability_matrix`
- `critical_rules`
- `test_environment`

Las entradas deben corresponder al mismo target, versión y snapshot.

## 4. Herramientas permitidas

- `lectura canónica`
- `validador de trazabilidad`
- `generación de matriz de cobertura`
- `clasificación de pruebas`

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

La escritura es reemplazo o enriquecimiento controlado dentro del objeto
autorizado. No modifica la fuente ni los outputs aprobados de otros workers.

## 7. Acciones prohibidas

- `modificar historias para hacer pasar pruebas`
- `omitir negativos`
- `crear pruebas sin expected result`
- `aprobar resultados`
- `inventar reglas`

También están prohibidos `VALIDATED`, `APPROVED`, `VIGENTE`,
`PRODUCTION_READY` y `PRODUCTION_AUTHORIZED`.

## 8. Protocolo de operación

1. Leer el Task Packet completo.
2. Verificar identidad, versión, SHA-256 y scopes.
3. Resolver referencias y outputs previos.
4. Ejecutar el procedimiento del agente.
5. Correr autoverificaciones.
6. Emitir objeto, evidencia y decisiones pendientes.
7. Entregar al juez independiente.
8. Reparar únicamente assertions fallidas.
9. Detener después del segundo reintento.

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
- `permission_without_negative_test = 0`
- `tenant_rule_without_cross_tenant_test = 0`
- `critical_error_without_test = 0`

Los indicadores se reportan con conteos y evidence refs, no con evaluaciones
subjetivas.

## 12. Reintentos y bloqueo

`retry_limit = 2`.

Bloquear cuando falte fuente, el scope sea insuficiente, exista contradicción
material, el output previo no haya pasado o la reparación requiera cambiar una
decisión de otro step.

## 13. Handoff mínimo

```json
{
  "worker_profile": "PERFIL_STORY_TEST_DERIVER_LF",
  "agent_ref": "agents/test-deriver.md",
  "target_ref": "<TARGET>",
  "source_snapshot_sha256": "<64-hex>",
  "written_sections": [],
  "assertion_results": {},
  "pending_decisions": [],
  "evidence_refs": [],
  "retry_count": 0,
  "next_judge": "J10_TEST_COVERAGE"
}
```

## 14. Fuentes de diseño no normativas

- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.
- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.

Los contratos LF prevalecen.
