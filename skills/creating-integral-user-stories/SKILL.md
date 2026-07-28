---
name: creating-integral-user-stories
description: >
  Use when a product screen, registered module, prototype, functional
  specification, handoff, or partial story set must be decomposed into complete,
  traceable and implementation-ready Story Packs with security, privacy,
  analytics, observability, auditability, accessibility and tests.
version: v0.3
status: CANDIDATO_READ_ONLY
operation_code: BUILD_INTEGRAL_STORY_CREATOR_LF
runtime: disabled
---

# Creating Integral User Stories

## 1. Misión

Convertir una fuente funcional verificable en historias de usuario atómicas,
completas y trazables. Cada historia se entrega como un **Story Pack A–Q** y
pasa por jueces independientes. La skill no aprueba su propio trabajo, no
habilita runtime, no autoriza producción y no hace merge.

```text
fuente verificable
→ snapshot + SHA-256
→ inventarios de pantalla
→ unidades funcionales
→ decisión por unidad
→ Story Packs A–Q
→ pruebas
→ jueces independientes
→ evidencia y ledger binario
```

## 2. Definición de completo

Una historia no está completa por tener solamente actor, necesidad y beneficio.
Debe incluir, cuando aplique:

1. identidad y trazabilidad;
2. núcleo funcional;
3. interacción;
4. contrato por campo;
5. validaciones;
6. observaciones;
7. errores;
8. seguridad y privacidad;
9. estados e integridad;
10. auditoría;
11. tokens y mensajes;
12. analytics;
13. observabilidad;
14. responsive y accesibilidad;
15. pruebas;
16. dependencias, riesgos y decisiones pendientes;
17. jueces y evidencia.

La ausencia silenciosa de una sección aplicable es una falla. Una definición que
la fuente no permite confirmar se registra como `PENDING_DECISION`; nunca se
completa con una inferencia presentada como hecho.

## 3. Activación

Activar cuando exista al menos uno de estos objetos:

- pantalla registrada;
- módulo o flujo funcional;
- prototipo con comportamiento identificable;
- especificación funcional;
- handoff de producto;
- historias parciales que deben completarse;
- backlog que conserva referencia a una fuente operativa;
- solicitud explícita de criterios, campos, seguridad, observabilidad o pruebas
  para una pantalla o flujo.

### No activar

No activar para:

- traducción, resumen o redacción libre;
- priorización sin fuente funcional;
- ideación sin pantalla, flujo ni requerimiento verificable;
- aprobación o declaración de vigencia;
- implementación de código sin Story Pack;
- solicitudes para saltar jueces, evidencia o restricciones.

Si el pedido parece relacionado pero no existe fuente suficiente, activar en
modo `NEEDS_SOURCE_CONTEXT` y detener la generación del paquete.

## 4. Entradas mínimas

| Entrada | Obligatoria | Regla |
|---|---:|---|
| `target` | Sí | `screen_code`, módulo o conjunto de historias parciales |
| `source_snapshot` | Sí | versión, contenido o referencia resoluble y SHA-256 |
| `task_packet` | Sí para ejecución delegada | valida contra `schemas/task-packet.schema.json` |
| inventarios | Según step | contextos, permisos, campos, transiciones y relaciones |
| decisiones pendientes | Sí, aunque esté vacío | no cerrar sin evidencia |
| contrato GitHub | Solo transporte | repo, rama, base, restricciones y readback |

## 5. Preflight bloqueante

Antes de cualquier derivación:

1. confirmar que el target existe en la fuente;
2. confirmar versión y SHA-256;
3. resolver referencias internas;
4. confirmar alcance de lectura y escritura;
5. confirmar worker y juez asignados;
6. verificar que el worker no ejecutará su propio juez;
7. identificar conflictos y decisiones pendientes;
8. fijar el inventario esperado de salidas.

Detener con `BLOCKED` cuando:

```text
operational_source_unavailable = true
source_snapshot_missing = true
source_hash_missing = true
target_not_found = true
source_version_conflict = true
write_scope_not_authorized = true
judge_independence_broken = true
```

## 6. Decisiones de descomposición

Cada unidad funcional recibe exactamente una decisión:

```text
CREATE_STORY
MERGE_WITH
CROSS_CUTTING
OUT_OF_SCOPE
PENDING_DECISION
DUPLICATE
RELATED_SCREEN
```

Una decisión incluye justificación, clasificación y `source_ref`. No se crean
historias por cada pestaña, botón o paso visual. Se separa por actor, permiso,
resultado observable, estado, riesgo o recurso persistido.

## 7. Flujo obligatorio y jueces

| Orden | Step | Worker principal | Juez | Resultado exigido |
|---:|---|---|---|---|
| 1 | Integridad de fuente | Screen Decomposer | J01 | `PASS_WITH_EVIDENCE` |
| 2 | Descomposición | Screen Decomposer | J02 | `PASS_WITH_EVIDENCE` |
| 3 | Núcleo A–B | Story Core Author | J03 | `PASS_WITH_EVIDENCE` |
| 4 | Campos | Field Contract Author | J04 | `PASS_WITH_EVIDENCE` |
| 5 | Observaciones y errores | Cross Cutting Enricher | J05 | `PASS_WITH_EVIDENCE` |
| 6 | Seguridad y privacidad | Cross Cutting Enricher | J06 | `PASS_WITH_EVIDENCE` |
| 7 | Auditoría y trazabilidad | Cross Cutting Enricher | J07 | `PASS_WITH_EVIDENCE` |
| 8 | Tokens y mensajes | Cross Cutting Enricher | J08 | `PASS_WITH_EVIDENCE` |
| 9 | Analytics y observabilidad | Cross Cutting Enricher | J09 | `PASS_WITH_EVIDENCE` |
| 10 | Pruebas | Test Deriver | J10 | `PASS_WITH_EVIDENCE` |
| 11 | Paquete | Orquestador independiente | J11 | `PASS_WITH_EVIDENCE` |
| 12 | GitHub | Orquestador independiente | J12 | `PASS_WITH_EVIDENCE` o N/A autorizado |
| 13 | Cierre | Orquestador independiente | J13 | `PASS_WITH_EVIDENCE` |

## 8. Contrato de workers

Los workers reciben un Task Packet y solo pueden:

- leer referencias declaradas;
- escribir las secciones autorizadas;
- emitir evidencia;
- reparar assertions fallidas dentro del alcance;
- retornar `READY_FOR_JUDGE`, `RETURN_TO_WORKER` o `BLOCKED`.

No pueden:

- cambiar la decisión del step anterior;
- crear hechos sin fuente;
- ejecutar el juez que aprueba su resultado;
- reducir umbrales para lograr PASS;
- marcar `VALIDATED`, `APPROVED`, `VIGENTE` o `PRODUCTION_READY`.

`retry_limit = 2`. Después de dos reparaciones fallidas, el step queda
`BLOCKED` con evidencia.

## 9. Progressive disclosure

Cargar solo lo necesario para el step actual:

- `references/`: reglas operativas y contratos;
- `schemas/`: forma machine-checkable;
- `agents/`: procedimiento del worker;
- `perfiles/`: identidad, permisos y límites del worker;
- `judges/`: criterio independiente de aceptación;
- `scripts/`: validación determinista;
- `evals/`: regresión;
- `templates/`: forma de salida.

El archivo raíz orquesta; no reemplaza los contratos especializados.

## 10. Salidas

La ejecución produce:

```text
source_snapshot
screen_decomposition
coverage_report
story_pack[] 
judge_result[]
execution_ledger
execution_report
github_readback_evidence (si aplica)
```

Todos los objetos deben incluir referencias de evidencia resolubles. El cierre
se calcula desde el ledger; no se informa un porcentaje estimado.

## 11. Reglas de evidencia

- Hash de contenido: SHA-256 sobre UTF-8, LF, sin BOM y newline final.
- Cada regla de negocio tiene `source_ref`.
- Cada criterio tiene prueba o justificación de no aplicabilidad.
- Cada mutación tiene contrato de auditoría.
- Cada evento de analytics es libre de PII.
- Cada lectura o mutación multiempresa tiene prueba cross-tenant negativa.
- Cada resultado de juez declara assertions y reparaciones.

## 12. Stop conditions

La ejecución se detiene y reporta el punto exacto cuando:

- falta una fuente obligatoria;
- existe contradicción material;
- se requiere DDL, producción, runtime o merge sin autorización;
- el target branch cambió;
- una reparación excede el alcance;
- un juez crítico no pasa después de dos reintentos;
- el readback no coincide con el contenido canónico.

## 13. Ejemplo de activación

**Pedido:** “Tengo una pantalla de aprobación con operador y supervisor.
Necesito historias completas, seguridad y pruebas.”

**Respuesta operativa esperada:**

```text
ACTIVATE
→ solicitar/leer fuente
→ snapshot
→ J01
→ descomposición por resultados y permisos
→ Story Packs
→ controles de aprobación/rechazo/observación
→ pruebas positivas, negativas y cross-tenant
→ jueces y evidencia
```

## 14. Ejemplo de bloqueo

**Pedido:** “La pantalla se llama Gestión. Completa todo como consideres.”

```json
{
  "activation": "NEEDS_SOURCE_CONTEXT",
  "result": "BLOCKED",
  "blocking_assertions": [
    "operational_source_unavailable = true",
    "business_results_undefined = true"
  ],
  "must_not_invent": true
}
```

## 15. Límites duros

```text
NO_VALIDATED: true
NO_PRODUCCION: true
NO_RUNTIME_REAL: true
NO_DIRECT_MAIN_WRITE: true
NO_MERGE: true
NO_MARCAR_VIGENTE: true
```

## 16. Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.

Los patrones externos mejoran ejecutabilidad, validación y claridad. Los
contratos LF y la fuente operativa prevalecen ante cualquier conflicto.
