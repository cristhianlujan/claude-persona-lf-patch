# Contrato canónico del Story Pack v0.5

Jueces asociados por etapa:

- `J03_STORY_CORE` valida exclusivamente A–B.
- `J11_SKILL_PACKAGE` valida el Story Pack A–Q completo.

Schema canónico: `schemas/story-pack.schema.json`.  
Runtime J03: `scripts/validate_story_pack.py`.

## 1. Objetivo

Definir un Story Pack A–Q implementable, trazable y verificable mediante una
construcción por etapas. El contrato completo sigue siendo A–Q, pero ningún
worker puede exigir, escribir o validar secciones que pertenecen a una etapa
posterior.

Una regla no respaldada por fuente se registra como `PENDING_DECISION`; nunca
se presenta como confirmada. Ningún worker ejecuta su propio juez ni selecciona
su propio resultado de aprobación.

## 2. Secuencia normativa

```text
J02_SCREEN_DECOMPOSITION PASS_WITH_EVIDENCE
→ A04 STORY_CORE_AUTHOR escribe solo A identity + B core
→ J03_STORY_CORE valida solo A–B mediante sus subschemas
→ workers posteriores completan C–P dentro de sus scopes
→ Q judges_evidence consolida resultados independientes
→ J11_SKILL_PACKAGE valida A–Q completo
```

### 2.1 Etapa A04/J03

A04 recibe una única unidad funcional con `decision = CREATE_STORY` y produce
un envelope con exactamente:

```text
target_functional_unit
story_core.identity
story_core.core
source_snapshot
j02_evidence
```

A04 no escribe C–Q. J03 no exige C–Q, `context_budget`, `judges_evidence` ni
validación del Story Pack completo. J03 valida:

- el envelope;
- `identity` contra `schemas/story-pack.schema.json#properties/identity`;
- `core` contra `schemas/story-pack.schema.json#properties/core`;
- target, decisión, versión, SHA y evidencia J02;
- atomicidad;
- criterios Given–When–Then con `source_ref`;
- decisiones bloqueantes;
- independencia worker–juez.

### 2.2 Etapas posteriores

Solo después de J03 `PASS_WITH_EVIDENCE` se completan C–P mediante workers y
jueces especializados. Q se completa cuando existe evidencia independiente de
los jueces requeridos.

### 2.3 Cierre J11

J11 exige el objeto A–Q completo conforme al schema canónico. El Story Pack no
se considera cerrado por un PASS de J03; J03 aprueba únicamente el núcleo A–B.

## 3. Entradas por etapa

### A04/J03

| Entrada | Regla |
|---|---|
| `target_functional_unit` | Una sola unidad aprobada por J02 con `CREATE_STORY`. |
| `source_snapshot` | Versión, SHA-256, contenido/ref y referencias resueltas. |
| `task_packet` | Scope A–B, worker, juez, assertions y retry. |
| `j02_evidence` | `PASS_WITH_EVIDENCE` y evidencia resoluble. |

### Construcción C–Q

| Entrada | Regla |
|---|---|
| `story_core` | A–B aprobado por J03. |
| `source_snapshot` | El mismo snapshot y SHA usados en A–B. |
| `registries` | Permisos, campos, tokens, mensajes y catálogos autorizados. |
| `task_packet` | Scope exacto de la sección asignada. |
| `prior_judge_evidence` | Evidencia de pasos anteriores. |

## 4. Contrato A–Q

```text
A identity                 J audit
B core                     K tokens_messages
C interaction              L analytics
D fields                   M observability
E validations              N responsive_accessibility
F observations             O tests
G errors                   P dependencies_risks
H security_privacy         Q judges_evidence
I states
```

`screen_fields` es un índice opcional y no agrega una sección.

### A. identity

```text
story_code, title, epic_code, module_code, screen_code,
functional_unit_code, source_decision_id, source_version,
source_snapshot_sha, status, priority
```

### B. core

```text
actor, need, benefit, preconditions, trigger, main_flow,
alternative_flows, postconditions, acceptance_criteria, out_of_scope
```

Cada criterio requiere `criterion_code`, `given`, `when`, `then` y
`source_ref`. Los códigos son únicos.

### C–O

- C declara entradas, acciones, permisos, estados UI y navegación.
- D aplica `references/field-contract.md`.
- E–G declaran reglas, observaciones y errores con recuperación.
- H exige frontera tenant y negativo cross-tenant.
- I cubre transiciones, idempotencia y concurrencia cuando aplique.
- J define auditoría.
- K usa tokens y mensajes autorizados; no es presupuesto de contexto.
- L no contiene PII.
- M declara logs, métricas, trazas, umbrales y dashboard.
- N declara accesibilidad y responsive.
- O deriva pruebas positivas, negativas, permisos, tenant, errores y estados.

### P. dependencies_risks

P contiene:

```text
dependencies, risks, pending_decisions, context_budget
```

`context_budget` es obligatorio para el Story Pack completo y para J11, no para
A04/J03.

```json
{
  "measurement_method": "ANTHROPIC_COUNT_TOKENS|TOKENIZER|ESTIMATE",
  "canonical_story_tokens": 0,
  "implementation_view_tokens": 0,
  "active_context_tokens": 0,
  "context_band": "COMPACT|STANDARD|WARNING|DISCLOSURE_REQUIRED|DIRECT_LOAD_BLOCKED",
  "direct_load_allowed": true,
  "specialized_views_required": false,
  "atomicity_review_required": false,
  "atomicity_review_result": "NOT_REQUIRED|ATOMIC|SPLIT_REQUIRED|PENDING",
  "measured_at": "2026-07-28T00:00:00Z",
  "model_reference": "model-or-tokenizer-reference",
  "source_ref": "policy:event:795"
}
```

Reglas:

```text
canonical_story_tokens > 12000
  -> direct_load_allowed = false
  -> specialized_views_required = true
  -> atomicity_review_required = true

active_context_tokens > 15000
  -> direct_load_allowed = false

measurement_method missing
  -> RETURN_TO_WORKER
```

La longitud no sustituye el análisis de atomicidad. Se divide cuando existe más
de un resultado independiente, actor, frontera de permiso, recurso persistido,
ciclo de estado o riesgo separable.

### Q. judges_evidence

Q registra juez, versión, resultado, `compliance_bit`, assertions fallidas,
reparaciones, hashes, timestamps y `evidence_refs` resolubles.

## 5. Condiciones J03 — A–B

```text
input_envelope_valid = 0
identity_schema_valid = 0
core_schema_valid = 0
target_functional_unit_matches = 0
source_decision_matches = 0
source_snapshot_matches = 0
actor_missing = 0
need_missing = 0
benefit_missing = 0
preconditions_missing = 0
trigger_missing = 0
main_flow_missing = 0
postconditions_missing = 0
acceptance_criteria_missing = 0
criteria_without_given_when_then = 0
criteria_without_source_ref = 0
duplicate_criterion_codes = 0
out_of_scope_missing = 0
multiple_independent_results = 0
blocking_pending_decisions = 0
```

J03 debe producir 20/20 para PASS. No puede otorgar PASS cuando falta evidencia
J02, la unidad no es `CREATE_STORY`, existe una decisión bloqueante o el
runtime/registro/SHA no son reconciliables.

## 6. Condiciones J11 — A–Q

```text
required_sections_present = 17
stories_without_source_trace = 0
criteria_without_given_when_then = 0
duplicate_criterion_codes = 0
context_budget_missing = 0
context_budget_rule_violations = 0
schema_validation_errors = 0
judges_without_evidence = 0
```

Estas condiciones no se trasladan hacia atrás a A04/J03.

## 7. Casos de control J03

### Positivo

Un envelope con una unidad `CREATE_STORY`, A–B válidos, snapshot reconciliado y
evidencia J02 debe producir `PASS_WITH_EVIDENCE`, 20/20 assertions y salida
conforme a `schemas/judge-result.schema.json`.

### Negativos

Deben rechazarse o bloquearse individualmente:

1. evidencia J02 ausente;
2. decisión distinta de `CREATE_STORY`;
3. unidad funcional no coincidente;
4. decisión fuente no coincidente;
5. SHA del snapshot no coincidente;
6. actor ausente;
7. trigger ausente;
8. flujo principal vacío;
9. criterio sin `given`;
10. criterio sin `source_ref`;
11. código de criterio duplicado;
12. `out_of_scope` ausente;
13. múltiples resultados independientes;
14. decisión bloqueante;
15. identidad del ejecutor ausente;
16. SHA del runtime no reconciliado.

## 8. Casos de control J11

El positivo requiere A–Q completo, schema válido, presupuesto coherente y
evidencia de jueces. El negativo debe rechazar, como mínimo, una sección
ausente, criterio inválido, presupuesto incoherente o juez sin evidencia.

## 9. Stop conditions y reparación

- A04 repara únicamente A–B.
- Workers posteriores reparan únicamente sus secciones.
- J03 no puede exigir C–Q para corregir A–B.
- J11 no puede utilizar un PASS de J03 como sustituto de A–Q completo.
- Está prohibido borrar assertions, reducir umbrales, inventar fuente o
  autoaprobar.
- `retry_limit = 2`; al agotarse, retornar `BLOCKED` con evidencia acumulada.

## 10. Invariantes de independencia

```text
worker_identity != judge_identity
worker_must_not_execute_own_judge = true
J03_scope = A_B_ONLY
J11_scope = A_Q_COMPLETE
context_budget_required_at_J03 = false
context_budget_required_at_J11 = true
```

## 11. Handoffs

### A04 → J03

Incluye el envelope A–B, target, snapshot, evidencia J02, autoverificaciones,
identidad del worker, versión, hashes, timestamps, retry y evidencia.

### J03 → siguiente worker

Incluye resultado independiente, 20 assertions, reparaciones, evidencia y
referencia al A–B aprobado. No crea C–Q.

### Workers C–P → J11

Cada worker entrega su sección y evidencia. J11 recibe el Story Pack completo y
Q consolidado.

## 12. Precedencia

Ante conflicto:

1. Task Packet específico y más restrictivo;
2. contrato del juez de la etapa;
3. perfil del worker;
4. agente;
5. este contrato general;
6. patrones externos no normativos.

Los scopes no se expanden por inferencia.
