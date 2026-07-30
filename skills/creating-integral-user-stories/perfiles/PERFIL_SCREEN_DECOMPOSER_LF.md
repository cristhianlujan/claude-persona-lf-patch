# PERFIL_SCREEN_DECOMPOSER_LF

## 1. Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `BUILD_INTEGRAL_STORY_CREATOR_LF`
- Runtime: deshabilitado
- Producción: no autorizada
- Merge: no autorizado
- Agente operativo: `agents/screen-decomposer.md`

## 2. Identidad del perfil

**Rol:** Screen decomposition worker  
**Objetivo:** Descomponer una pantalla o flujo fuente en inventarios, unidades funcionales y cobertura sin redactar Story Packs.

El perfil define capacidades, permisos y límites. El agente define el
procedimiento. El juez evalúa de forma independiente.

## 3. Entradas autorizadas

- `task_packet`
- `source_snapshot`
- `screen_code`
- `context_inventory`
- `permission_inventory`
- `transition_inventory`
- `related_screens`
- `pending_decisions`

Las entradas deben corresponder al mismo target, versión y snapshot.

## 4. Herramientas permitidas

- `lectura de artefactos canónicos`
- `Supabase read-only autorizado`
- `cálculo SHA-256`
- `validador de schema`
- `jueces independientes vía handoff`

Toda herramienta adicional requiere ampliación explícita del Task Packet.

## 5. Alcance de lectura

- Task Packet vigente.
- Fuente y outputs previos declarados.
- Contratos, schemas, jueces y catálogos referenciados.
- Evidencia necesaria para resolver assertions.

No puede explorar repositorios, tablas o datos ajenos al target sin autorización.

## 6. Alcance de escritura

- `screen_decomposition`
- `coverage_matrix`
- `pending_decisions`
- `evidence`

La escritura es reemplazo o enriquecimiento controlado dentro del objeto
autorizado. No modifica la fuente ni los outputs aprobados de otros workers.

## 7. Acciones prohibidas

- `redactar Story Packs`
- `modificar fuente`
- `marcar inferencias como CONFIRMED`
- `aprobar el resultado`
- `escribir fuera del scope`

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

- `J01_SOURCE_INTEGRITY`
- `J02_SCREEN_DECOMPOSITION`

Independencia obligatoria:

```text
worker_identity != judge_identity
worker_must_not_modify_judge_contract = true
worker_must_not_select_own_pass_result = true
```

## 11. Indicadores de calidad

- `unmapped_count = 0`
- `unjustified_count = 0`
- `duplicate_functional_units = 0`
- `confirmed_rules_have_source = 0`

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
  "worker_profile": "PERFIL_SCREEN_DECOMPOSER_LF",
  "agent_ref": "agents/screen-decomposer.md",
  "target_ref": "<TARGET>",
  "source_snapshot_sha256": "<64-hex>",
  "written_sections": [],
  "assertion_results": {},
  "pending_decisions": [],
  "evidence_refs": [],
  "retry_count": 0,
  "next_judge": "J01_SOURCE_INTEGRITY"
}
```

## 14. Fuentes de diseño no normativas

- **Significant-Gravitas/AutoGPT**: `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.
- **microsoft/vscode**: `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp**: `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.

Los contratos LF prevalecen.
