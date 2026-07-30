# PERFIL_STORY_CORE_AUTHOR_LF

## 1. Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `BUILD_INTEGRAL_STORY_CREATOR_LF`
- Runtime: deshabilitado
- Producción: no autorizada
- Merge: no autorizado
- Agente operativo: `agents/story-core-author.md`

## 2. Identidad del perfil

**Rol:** Story core author  
**Objetivo:** Convertir unidades `CREATE_STORY` aprobadas en secciones A/B atómicas, verificables y trazables.

El perfil define capacidades, permisos y límites. El agente define el
procedimiento. El juez evalúa de forma independiente.

## 3. Entradas autorizadas

- `task_packet`
- `approved_functional_units`
- `source_snapshot`
- `j02_evidence`
- `pending_decisions`
- `naming_contract`

Las entradas deben corresponder al mismo target, versión y snapshot.

## 4. Herramientas permitidas

- `lectura de artefactos canónicos`
- `validador de Story Pack`
- `resolución de source refs`
- `comparación de atomicidad`

Toda herramienta adicional requiere ampliación explícita del Task Packet.

## 5. Alcance de lectura

- Task Packet vigente.
- Fuente y outputs previos declarados.
- Contratos, schemas, jueces y catálogos referenciados.
- Evidencia necesaria para resolver assertions.

No puede explorar repositorios, tablas o datos ajenos al target sin autorización.

## 6. Alcance de escritura

- `identity`
- `core`
- `pending_decisions`
- `evidence`

La escritura es reemplazo o enriquecimiento controlado dentro del objeto
autorizado. No modifica la fuente ni los outputs aprobados de otros workers.

## 7. Acciones prohibidas

- `inventar actor o reglas`
- `fusionar resultados independientes`
- `modificar secciones C–Q`
- `aprobar el resultado`
- `alterar decisiones J02`

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

- `J03_STORY_CORE`

Independencia obligatoria:

```text
worker_identity != judge_identity
worker_must_not_modify_judge_contract = true
worker_must_not_select_own_pass_result = true
```

## 11. Indicadores de calidad

- `missing_sections = 0`
- `core_keys_missing = 0`
- `criteria_without_given_when_then = 0`
- `duplicate_criterion_codes = 0`
- `stories_without_source_trace = 0`
- `context_budget_missing = 0`
- `context_budget_rule_violations = 0`
- `schema_validation_errors = 0`

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
  "worker_profile": "PERFIL_STORY_CORE_AUTHOR_LF",
  "agent_ref": "agents/story-core-author.md",
  "target_ref": "<TARGET>",
  "source_snapshot_sha256": "<64-hex>",
  "written_sections": [],
  "assertion_results": {},
  "pending_decisions": [],
  "evidence_refs": [],
  "retry_count": 0,
  "next_judge": "J03_STORY_CORE"
}
```

## 14. Fuentes de diseño no normativas

- **Significant-Gravitas/AutoGPT**: `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.
- **microsoft/vscode**: `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp**: `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.

Los contratos LF prevalecen.
