# Plantilla integral de Story Pack

Versión operativa: `v0.4`.

Esta plantilla documenta las mismas secciones y restricciones que `schemas/story-pack.schema.json`. Para un ejemplo JSON válido y completo, usar `templates/story-pack.template.json`.

## A. Identidad y trazabilidad

| Campo | Regla |
|---|---|
| `story_code` | Código estable asignado por el proceso |
| `title` | Verbo, objeto y contexto observable |
| `module_code` / `screen_code` | Copia exacta de la fuente |
| `functional_unit_code` | Unidad aprobada por J02 |
| `source_decision_id` | Decisión que originó la historia |
| `source_version` / `source_snapshot_sha` | Versión y hash usados |
| `status` | CANDIDATO_READ_ONLY, PENDING_DECISION o BLOCKED |
| `priority` | P0–P3, solo si está confirmada |

## B. Núcleo funcional

```text
Actor:
Necesidad:
Beneficio:
Precondiciones:
Disparador:
Flujo principal:
Flujos alternativos:
Postcondiciones:
Fuera de alcance:
```

Cada criterio usa `criterion_code`, `given`, `when`, `then` y `source_ref`.

## C. Contrato de interacción

Definir entradas, acción primaria, acciones secundarias, carga, estado vacío y confirmación. Prohibido inventar componentes o valores visuales.

## D. Contrato de campos

Una fila por cada `screen_field`. Incluir origen, tipo, required, edición, perfiles, visibilidad, PII, masking, analytics, logs, exportación, auditoría, retención, validaciones, mensajes y tokens.

## E. Validaciones

Cada regla tiene código, campo, condición, error, criticidad y `source_ref`.

## F. Observaciones

Cada observación tiene código, severidad, bloqueo, continuación, acción, `message_code`, auditoría y `source_ref`.

## G. Errores

Cada error tiene código único, severidad, retry, mensaje, correlación, auditoría, alerta y detalle técnico `INTERNAL_ONLY`.

## H. Seguridad y privacidad

Declarar autenticación, perfiles, permisos, `tenant_key`, política cross-tenant, enforcement server-side, RLS, MFA, rate limit, idempotencia y almacenamiento.

## I. Estados e integridad

Declarar estado inicial, transiciones permitidas y prohibidas, concurrencia y efectos persistentes.

## J. Auditoría

Definir eventos por mutación o descarga sensible, estrategias de valores, permiso usado, correlación e idempotencia.

## K. Tokens y mensajes

Referenciar tokens registrados o candidatos. Todo mensaje tiene código, severidad, audiencia, `text_ref`, acción y tono.

## L. Analytics

Solo eventos útiles, libres de PII, con trigger, propiedades seguras, correlation_id, sampling y retención.

## M. Observabilidad

Métricas, logs enmascarados, alertas y umbrales. No mezclar con auditoría.

## N. Responsive y accesibilidad

Breakpoints, reflow, orden de contenido, foco, teclado, labels, anuncio de errores, reduced motion e indicadores no basados solo en color.

## O. Casos de prueba

Cada prueba referencia criterio o regla, define precondiciones, pasos, resultado esperado, negativo, tenant, actor y `evidence_path`. Los fixtures exactos se mantienen como evidencia externa consumida por J10.

## P. Dependencias, riesgos, decisiones y presupuesto de contexto

Registrar dependencias, riesgos y decisiones pendientes. `context_budget` es obligatorio e incluye:

```text
measurement_method
canonical_story_tokens
implementation_view_tokens
active_context_tokens
context_band
direct_load_allowed
specialized_views_required
atomicity_review_required
atomicity_review_result
measured_at
model_reference
source_ref
```

Reglas:

- `canonical_story_tokens > 12000` obliga `direct_load_allowed=false`, revisión de atomicidad y vistas especializadas.
- `active_context_tokens > 15000` bloquea carga directa.
- No estimar como medición exacta; registrar el método real.

## Q. Jueces y evidencia

Cada resultado usa el envelope de `schemas/judge-result.schema.json` v0.5: ejecutor, comando, timestamps, conteos de assertions, fallas, bloqueos, reparaciones, evidencia y hashes.

## Casos de control

### Positivo

El JSON completo valida contra el schema, contiene `context_budget`, pruebas trazables y evidencia de jueces resoluble.

### Negativo

Un Story Pack sin `context_budget`, con carga directa por encima del límite o una prueba sin referencia debe ser rechazado.

## Reglas de uso

1. Validar el JSON contra el schema.
2. Ejecutar los validadores aplicables.
3. No borrar secciones para ocultar una falla.
4. No usar datos personales reales en ejemplos o pruebas.
5. No declarar PASS desde un worker.
6. Después de dos reparaciones fallidas, retornar BLOCKED.

## Benchmark dual verificado

Fecha: `2026-07-30`.

- **Claude Skills — anthropics/skills:** `skills/skill-creator/SKILL.md`, blob `65b3a402dbd09b8e83f9d637c6b553875189085c`; progressive disclosure, outputs exactos, evals y reparación.
- **freeCodeCamp/freeCodeCamp:** `curriculum/schema/challenge-schema.js`, blob `7db60817942625110525fd313bf80f1df067f006`; validación condicional y constraints explícitos.
- **Significant-Gravitas/AutoGPT:** `classic/original_autogpt/CLAUDE.md`, blob `9c6d04300f83621b00e804298b7b8ea9ce3953c7`; límites de ciclo, estado y carga de contexto.

**Hallazgo diferencial incorporado:** el presupuesto de contexto se convierte en parte obligatoria del entregable y del criterio de atomicidad.
