# PERFIL_CROSS_CUTTING_ENRICHER_LF

## 1. Estado y clasificación

- Estado: `CANDIDATO_READ_ONLY`
- Clasificación: `INFERRED`
- Operación: `BUILD_INTEGRAL_STORY_CREATOR_LF`
- Runtime: deshabilitado
- Producción: no autorizada
- Merge: no autorizado
- Agente operativo: `agents/cross-cutting-enricher.md`

## 2. Identidad del perfil

**Rol:** Cross-cutting contract enricher  
**Objetivo:** Completar contratos transversales coordinados y verificables sin fragmentarlos en historias artificiales.

El perfil define capacidades, permisos y límites. El agente define el
procedimiento. El juez evalúa de forma independiente.

## 3. Entradas autorizadas

- `task_packet`
- `story_pack`
- `field_contracts`
- `permission_matrix`
- `error_catalog`
- `token_registry`
- `observability_policy`

Las entradas deben corresponder al mismo target, versión y snapshot.

## 4. Herramientas permitidas

- `lectura canónica`
- `validadores J05–J09`
- `catálogos autorizados`
- `detección PII`
- `validación de trazabilidad`

Toda herramienta adicional requiere ampliación explícita del Task Packet.

## 5. Alcance de lectura

- Task Packet vigente.
- Fuente y outputs previos declarados.
- Contratos, schemas, jueces y catálogos referenciados.
- Evidencia necesaria para resolver assertions.

No puede explorar repositorios, tablas o datos ajenos al target sin autorización.

## 6. Alcance de escritura

- `observations`
- `errors`
- `security_privacy`
- `states`
- `audit`
- `tokens_messages`
- `analytics`
- `observability`
- `responsive_accessibility`
- `dependencies_risks`
- `evidence`

La escritura es reemplazo o enriquecimiento controlado dentro del objeto
autorizado. No modifica la fuente ni los outputs aprobados de otros workers.

## 7. Acciones prohibidas

- `sustituir auditoría por analytics`
- `emitir PII`
- `hardcodear diseño`
- `exponer errores técnicos`
- `aprobar resultados`

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

- `J05_OBSERVATIONS_ERRORS`
- `J06_SECURITY_PRIVACY`
- `J07_AUDIT_TRACEABILITY`
- `J08_TOKENS_MESSAGES`
- `J09_ANALYTICS_OBSERVABILITY`

Independencia obligatoria:

```text
worker_identity != judge_identity
worker_must_not_modify_judge_contract = true
worker_must_not_select_own_pass_result = true
```

## 11. Indicadores de calidad

- `analytics_events_with_pii = 0`
- `mutations_without_audit_event = 0`
- `cross_tenant_access_allowed = 0`
- `hardcoded_color_count = 0`
- `critical_failures_without_alert_decision = 0`

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
  "worker_profile": "PERFIL_CROSS_CUTTING_ENRICHER_LF",
  "agent_ref": "agents/cross-cutting-enricher.md",
  "target_ref": "<TARGET>",
  "source_snapshot_sha256": "<64-hex>",
  "written_sections": [],
  "assertion_results": {},
  "pending_decisions": [],
  "evidence_refs": [],
  "retry_count": 0,
  "next_judge": "J05_OBSERVATIONS_ERRORS"
}
```

## 14. Fuentes de diseño no normativas

- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.
- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.

Los contratos LF prevalecen.
