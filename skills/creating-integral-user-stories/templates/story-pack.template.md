# Plantilla integral de Story Pack

Versión operativa: `v0.3`.

Esta plantilla documenta las mismas secciones y restricciones que
`schemas/story-pack.schema.json`. Para un ejemplo JSON válido y completo, usar
`templates/story-pack.template.json`.

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

Cada criterio usa esta estructura:

```yaml
criterion_code: AC-DOMAIN-001
given: estado inicial verificable
when: acción o evento único
then: resultado observable
source_ref: SRC-001#rule
```

## C. Contrato de interacción

Definir entradas, acción primaria, acciones secundarias, carga, estado vacío y
confirmación. Prohibido inventar componentes o valores visuales.

## D. Contrato de campos

Una fila por cada `screen_field`. Incluir origen, tipo, required, edición,
perfiles, visibilidad, PII, masking, analytics, logs, exportación, auditoría,
retención, validaciones, mensajes y tokens.

## E. Validaciones

Cada regla tiene código, campo, condición, error, criticidad y source_ref.

## F. Observaciones

Cada observación tiene código, severidad, bloqueo, continuación, acción,
message_code, auditoría y source_ref.

## G. Errores

Cada error tiene código único, severidad, retry, mensaje, correlación,
auditoría, alerta y detalle técnico INTERNAL_ONLY.

## H. Seguridad y privacidad

Declarar autenticación, perfiles, permisos, tenant_key, política cross-tenant,
enforcement server-side, RLS, MFA, rate limit, idempotencia y almacenamiento.

## I. Estados e integridad

Declarar estado inicial, transiciones permitidas y prohibidas, concurrencia y
efectos persistentes.

## J. Auditoría

Definir eventos por mutación o descarga sensible, estrategias de valores,
permiso usado, correlación e idempotencia.

## K. Tokens y mensajes

Referenciar tokens registrados o candidatos. Todo mensaje tiene código,
severidad, audiencia, text_ref, acción y tono.

## L. Analytics

Solo eventos útiles, libres de PII, con trigger, propiedades seguras,
correlation_id, sampling y retención.

## M. Observabilidad

Métricas, logs enmascarados, alertas y umbrales. No mezclar con auditoría.

## N. Responsive y accesibilidad

Breakpoints, reflow, orden de contenido, foco, teclado, labels, anuncio de
errores, reduced motion e indicadores no basados solo en color.

## O. Casos de prueba

Cada prueba referencia criterio o regla, define precondiciones, pasos, resultado
esperado, tipo negativo, tenant, actor y evidence_path.

## P. Dependencias, riesgos y decisiones

Registrar dependencias con estado, riesgos con nivel y mitigación, y decisiones
pendientes con los campos bloqueados.

## Q. Jueces y evidencia

| Juez | Resultado | Bit | Fallas | Evidencia |
|---|---|---:|---|---|
| J03_STORY_CORE | PASS_WITH_EVIDENCE | 1 | vacío | ruta resoluble |

## Reglas de uso

1. Validar el JSON contra el schema.
2. Ejecutar los validadores aplicables.
3. No borrar secciones para ocultar una falla.
4. No usar datos personales reales en ejemplos o pruebas.
5. No declarar PASS desde un worker.
6. Después de dos reparaciones fallidas, retornar BLOCKED.

## Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.
- **huggingface/transformers** (~162,000 estrellas): `docs/source/en/testing.md`; patrones: arquitectura de pruebas reutilizable, casos rápidos y lentos, regresión y cobertura negativa.
