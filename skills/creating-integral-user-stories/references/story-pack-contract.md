# Contrato canónico del Story Pack v0.4

Jueces asociados: `J03_STORY_CORE` y `J11_SKILL_PACKAGE`.
Esquema: `schemas/story-pack.schema.json`.
Validador: `scripts/validate_story_pack.py`.

## 1. Objetivo

Definir un Story Pack A–Q implementable, trazable y verificable. Cada sección
aplicable debe existir. Una regla no respaldada por fuente se registra como
`PENDING_DECISION`; nunca se presenta como confirmada.

## 2. Entradas obligatorias

| Entrada | Regla |
|---|---|
| `screen_decomposition` | Debe haber pasado J02 y contener unidad funcional y decisión fuente. |
| `source_snapshot` | Incluye versión y SHA-256 de la fuente usada. |
| `task_packet` | Declara alcance, worker, juez, assertions y evidencia. |
| `registries` | Permisos, campos, tokens, mensajes y catálogos disponibles. |

## 3. Procedimiento determinista

1. Crear A Identidad y B Núcleo funcional desde la misma fuente.
2. Completar C Interacción y D Campos sin inventar componentes.
3. Derivar E Validaciones, F Observaciones y G Errores.
4. Definir H Seguridad, I Estados, J Auditoría y K Tokens/mensajes.
5. Separar L Analytics de M Observabilidad.
6. Completar N Accesibilidad, O Pruebas y P Dependencias/riesgos.
7. Registrar Q Jueces y evidencia; ningún worker se autoaprueba.
8. Validar contra el schema y ejecutar casos positivo y negativo.

## 4. Contrato de salida A–Q

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

`screen_fields` es un índice opcional de códigos y no agrega una sección nueva.

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

Cada criterio usa `criterion_code`, `given`, `when`, `then` y `source_ref`.

### C–O. Contratos transversales

- C declara entradas, acciones, permisos, estados UI y navegación.
- D aplica `references/field-contract.md` a cada campo.
- E–G declaran código, condición, mensaje, severidad y recuperación.
- H exige frontera tenant y prueba negativa cross-tenant.
- I exige transiciones, idempotencia y concurrencia cuando aplique.
- J registra actor, antes/después, timestamp, correlación y retención.
- K usa tokens y mensajes autorizados; no representa presupuesto de contexto.
- L no contiene PII y declara evento, trigger, propiedades y owner.
- M declara logs, métricas, trazas, umbrales y dashboard.
- N declara teclado, foco, lector de pantalla, contraste y touch target.
- O deriva pruebas positivas, negativas, permisos, tenant, errores y estados.

### P. dependencies_risks

```text
dependencies, risks, pending_decisions, context_budget
```

`context_budget` es obligatorio y queda dentro de `dependencies_risks`:

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

Política interna LF:

| Objeto | Preferido | Warning | Límite |
|---|---:|---:|---:|
| Story Index | 150–300 | 301–400 | 400 |
| Story Core A–B | 500–1000 | 1001–1500 | 1500 |
| Implementation View | 1500–3500 | 3501–4500 | 4500 |
| Story Pack canónico | 3000–8000 | 8001–12000 | 12000 |
| Contexto activo | 6000–12000 | 12001–15000 | 15000 |

Reglas bloqueantes:

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

La historia no se divide solo por longitud. Se divide cuando existe más de un
resultado independiente, actor, frontera de permiso, recurso persistido, ciclo
de estado o riesgo separable.

### Q. judges_evidence

Registra juez, resultado, `compliance_bit`, assertions fallidas, reparaciones y
`evidence_refs` resolubles. Sin Q no existe cierre satisfactorio.

## 5. Condiciones de paso

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

## 6. Stop conditions y reparación

Detener con `RETURN_TO_WORKER` ante fuente ausente, contradicción, sección
faltante, criterio sin GWT, schema inválido o presupuesto incoherente. Reparar
solo el objeto asociado; está prohibido borrar assertions, reducir umbrales o
inventar fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con evidencia.

## 7. Ejemplo positivo

```json
{
  "dependencies_risks": {
    "dependencies": [],
    "risks": [],
    "pending_decisions": [],
    "context_budget": {
      "measurement_method": "ESTIMATE",
      "canonical_story_tokens": 5200,
      "implementation_view_tokens": 2400,
      "active_context_tokens": 9000,
      "context_band": "STANDARD",
      "direct_load_allowed": true,
      "specialized_views_required": false,
      "atomicity_review_required": false,
      "atomicity_review_result": "NOT_REQUIRED",
      "measured_at": "2026-07-28T00:00:00Z",
      "model_reference": "estimate:utf8_chars_div_4",
      "source_ref": "policy:event:795"
    }
  }
}
```

Resultado esperado: `PASS_WITH_EVIDENCE` si el resto de A–Q también cumple.

## 8. Ejemplo negativo

```json
{
  "dependencies_risks": {
    "context_budget": {
      "canonical_story_tokens": 13100,
      "direct_load_allowed": true
    }
  }
}
```

Resultado esperado: `RETURN_TO_WORKER` por método ausente y carga directa
permitida sobre el límite. El fixture negativo debe ser rechazado por el
validador; si es aceptado, la cadena no se cierra.
