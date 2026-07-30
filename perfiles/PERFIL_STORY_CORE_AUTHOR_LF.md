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

El perfil define capacidades, permisos y límites. El agente define el procedimiento. El juez evalúa de forma independiente.

## 3. Entradas autorizadas

- `task_packet`
- `approved_functional_units`
- `source_snapshot`
- `j02_evidence`
- `pending_decisions`
- `naming_contract`
- `story_pack_schema`
- `context_budget`

Las entradas deben corresponder al mismo target, versión y snapshot. El Task Packet debe declarar los límites de contexto y el método de medición aplicable.

## 4. Herramientas permitidas

- `lectura de artefactos canónicos`
- `validador de Story Pack`
- `resolución de source refs`
- `comparación de atomicidad`
- `medición determinista de presupuesto de contexto`

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

La escritura es reemplazo o enriquecimiento controlado dentro del objeto autorizado. No modifica la fuente ni los outputs aprobados de otros workers.

## 7. Acciones prohibidas

- `inventar actor o reglas`
- `fusionar resultados independientes`
- `modificar secciones C–Q`
- `aprobar el resultado`
- `alterar decisiones J02`
- `omitir medición de contexto`
- `desactivar el schema para obtener PASS`

También están prohibidos `VALIDATED`, `APPROVED`, `VIGENTE`, `PRODUCTION_READY` y `PRODUCTION_AUTHORIZED`.

## 8. Protocolo de operación

1. Leer el Task Packet completo.
2. Verificar identidad, versión, SHA-256 y scopes.
3. Resolver referencias y outputs previos.
4. Confirmar presupuesto de contexto y método de medición.
5. Ejecutar el procedimiento del agente.
6. Validar la salida contra `schemas/story-pack.schema.json`.
7. Correr autoverificaciones y medir contexto.
8. Emitir objeto, evidencia y decisiones pendientes.
9. Entregar al juez independiente.
10. Reparar únicamente assertions fallidas.
11. Detener después del segundo reintento.

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

- `stories_without_actor = 0`
- `criteria_without_given_when_then = 0`
- `duplicate_criterion_codes = 0`
- `stories_with_multiple_independent_results = 0`
- `stories_without_source_trace = 0`
- `context_budget_missing = 0`
- `context_budget_rule_violations = 0`
- `schema_validation_errors = 0`

Los indicadores se reportan con conteos, valores actual/esperado y `evidence_refs`; no con evaluaciones subjetivas.

## 12. Reintentos y bloqueo

`retry_limit = 2`.

Bloquear cuando falte fuente, el scope sea insuficiente, exista contradicción material, el output previo no haya pasado, falte el método de medición de contexto o la reparación requiera cambiar una decisión de otro step.

## 13. Casos de control

### Caso positivo

Una unidad `CREATE_STORY` con J02 aprobado, snapshot hasheado, referencias resolubles, scope A/B y presupuesto de contexto declarado produce `READY_FOR_JUDGE`, schema válido y evidencia no vacía.

### Caso negativo

Una unidad con `source_ref` no resoluble, dos resultados de negocio independientes o carga directa por encima del límite retorna `BLOCKED` o `RETURN_TO_WORKER`; nunca genera una historia plausible ni elimina el control.

## 14. Handoff mínimo

```json
{
  "worker_profile": "PERFIL_STORY_CORE_AUTHOR_LF",
  "agent_ref": "agents/story-core-author.md",
  "target_ref": "<TARGET>",
  "source_snapshot_sha256": "<64-hex>",
  "written_sections": [],
  "assertion_results": {},
  "context_budget": {
    "measurement_method": "<METHOD>",
    "canonical_story_tokens": 0,
    "active_context_tokens": 0
  },
  "schema_validation_errors": 0,
  "pending_decisions": [],
  "evidence_refs": [],
  "retry_count": 0,
  "next_judge": "J03_STORY_CORE"
}
```

## 15. Benchmark dual verificado

Fecha de verificación: `2026-07-29`.

- **Claude Skills — anthropics/skills:** `skills/skill-creator/SKILL.md`, blob `65b3a402dbd09b8e83f9d637c6b553875189085c`; patrones aplicados: intención, activación, progressive disclosure, salidas exactas, evals objetivas e iteración.
- **Significant-Gravitas/AutoGPT — 185741 estrellas:** `classic/original_autogpt/CLAUDE.md`, blob `9c6d04300f83621b00e804298b7b8ea9ce3953c7`; complemento: presupuesto de ciclos, persistencia explícita, orden de componentes y gotchas operativos.
- **freeCodeCamp/freeCodeCamp — 453125 estrellas:** `curriculum/schema/challenge-schema.js`, blob `7db60817942625110525fd313bf80f1df067f006`; complemento: validaciones condicionales, unicidad y errores deterministas.

**Hallazgo diferencial incorporado:** el perfil ahora exige medición de contexto y validación de schema como evidencia de primera clase, no solo calidad editorial.

Los contratos LF prevalecen ante cualquier diferencia.
