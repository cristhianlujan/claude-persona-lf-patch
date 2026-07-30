---
name: creating-integral-user-stories
description: >
  Use when a product screen, registered module, prototype, functional
  specification, handoff, or partial story set must be decomposed into complete,
  traceable and implementation-ready Story Packs with security, privacy,
  analytics, observability, auditability, accessibility and tests.
version: v0.5
status: CANDIDATO_READ_ONLY
operation_code: BUILD_INTEGRAL_STORY_CREATOR_LF
runtime: disabled
---

# Creating Integral User Stories

## 1. Misión

Convertir una fuente funcional verificable en historias de usuario atómicas, completas y trazables. Cada historia se entrega como un **Story Pack A–Q**, pasa por jueces independientes y conserva evidencia resoluble desde la fuente hasta GitHub y Supabase.

```text
fuente + versión + SHA-256
→ integridad J01
→ descomposición J02
→ Story Pack A–Q J03–J09
→ pruebas J10
→ paquete J11
→ integridad GitHub J12
→ cierre binario J13
→ evidencia GitHub–Supabase
```

Esta skill no habilita runtime operativo, no autoriza producción, no hace merge, no publica release y no aprueba su propio trabajo.

## 2. Activación

Activar cuando exista al menos uno de estos objetos:

- pantalla registrada;
- módulo o flujo funcional;
- prototipo con comportamiento identificable;
- especificación funcional o handoff;
- backlog o historias parciales con fuente resoluble;
- solicitud explícita de campos, criterios, seguridad, observabilidad o pruebas.

### No activar

No activar para:

- traducción, resumen o redacción libre;
- ideación sin fuente funcional verificable;
- priorización sin evidencia;
- implementación de código sin Story Pack;
- declaración de vigencia, producción o aprobación;
- solicitudes para saltar jueces, pruebas o hashes.

Si el pedido es aplicable pero falta fuente, retornar `NEEDS_SOURCE_CONTEXT` y detener la derivación.

## 3. Entradas mínimas

| Entrada | Regla |
|---|---|
| `target` | Pantalla, módulo o conjunto de historias objetivo. |
| `source_snapshot` | Contenido, versión, referencia resoluble y SHA-256. |
| `task_packet` | Obligatorio para ejecución delegada; valida contra `schemas/task-packet.schema.json`. |
| inventarios | Contextos, campos, permisos, estados, transiciones y relaciones aplicables. |
| `pending_decisions` | Obligatorio aunque sea vacío. |
| contrato GitHub | Repo, rama, restricciones y readback. |

Todas las entradas deben pertenecer al mismo target, versión y snapshot.

## 4. Preflight bloqueante

Antes de escribir:

1. confirmar target, versión y SHA-256;
2. resolver referencias internas;
3. confirmar alcance de lectura y escritura;
4. confirmar worker y juez independientes;
5. fijar inventario esperado de outputs;
6. verificar dependencias y validadores;
7. detectar concurrencia y cambios posteriores;
8. registrar contradicciones y decisiones pendientes.

Retornar `BLOCKED` cuando ocurra cualquiera:

```text
operational_source_unavailable = true
source_snapshot_missing = true
source_hash_missing = true
target_not_found = true
source_version_conflict = true
write_scope_not_authorized = true
judge_independence_broken = true
required_validator_unavailable = true
concurrent_write_unreconciled = true
```

## 5. Flujo obligatorio J01–J13

| Orden | Step | Worker principal | Juez | Validador determinista |
|---:|---|---|---|---|
| 1 | Integridad de fuente | Screen Decomposer | J01 | `scripts/validate_source_integrity.py` |
| 2 | Descomposición | Screen Decomposer | J02 | `scripts/validate_screen_decomposition.py` |
| 3 | Núcleo A–B | Story Core Author | J03 | `scripts/validate_story_pack.py` |
| 4 | Campos | Field Contract Author | J04 | `scripts/validate_field_coverage.py` |
| 5 | Observaciones y errores | Cross Cutting Enricher | J05 | validadores de paquete |
| 6 | Seguridad y privacidad | Cross Cutting Enricher | J06 | `scripts/validate_security_coverage.py` |
| 7 | Auditoría y trazabilidad | Cross Cutting Enricher | J07 | `scripts/validate_traceability.py` |
| 8 | Tokens y mensajes | Cross Cutting Enricher | J08 | `scripts/validate_tokens.py` |
| 9 | Analytics y observabilidad | Cross Cutting Enricher | J09 | `scripts/detect_pii_telemetry.py` |
| 10 | Pruebas | Test Deriver | J10 | `scripts/validate_test_coverage.py` |
| 11 | Paquete | Orquestador independiente | J11 | `scripts/validate_package.py` |
| 12 | GitHub | Orquestador independiente | J12 | `scripts/validate_github_integrity.py` |
| 13 | Cierre | Orquestador independiente | J13 | `scripts/calculate_binary_completion.py` |

Cada step exige `PASS_WITH_EVIDENCE`. `retry_limit = 2`. Después de dos reparaciones fallidas, retornar `BLOCKED` con evidencia acumulada.

## 6. Contrato de workers

Los workers solo pueden:

- leer referencias declaradas;
- escribir secciones autorizadas;
- emitir evidencia y decisiones pendientes;
- reparar assertions fallidas dentro del scope;
- retornar `READY_FOR_JUDGE`, `RETURN_TO_WORKER` o `BLOCKED`.

No pueden autoaprobar, modificar decisiones previas, inventar hechos, reducir umbrales ni ejecutar su propio juez.

## 7. Story Pack A–Q

La salida canónica contiene:

```text
A identidad y trazabilidad
B núcleo funcional
C interacción
D contrato de campos
E validaciones
F observaciones
G errores
H seguridad y privacidad
I estados e integridad
J auditoría
K tokens y mensajes
L analytics
M observabilidad
N responsive y accesibilidad
O pruebas
P dependencias, riesgos, decisiones y context_budget
Q jueces y evidencia
```

La ausencia silenciosa de una sección aplicable es falla. Lo no confirmado se registra como `PENDING_DECISION`, nunca como hecho.

## 8. Progressive disclosure y contexto

Cargar solo lo necesario para el step actual:

- `references/`: contratos normativos;
- `schemas/`: forma machine-checkable;
- `agents/`: procedimiento;
- `perfiles/`: identidad, permisos y límites;
- `judges/`: aceptación independiente;
- `scripts/`: validación determinista;
- `evals/`: positivos y negativos;
- `templates/`: forma de salida.

`context_budget` es obligatorio. Un Story Pack sobre el límite no puede cargarse directamente; requiere vistas especializadas y revisión de atomicidad.

## 9. Benchmark dual obligatorio

Cada artefacto se compara individualmente contra:

### A. Claude Skills

Referencia base:

```text
repository: anthropics/skills
path: skills/skill-creator/SKILL.md
blob: 65b3a402dbd09b8e83f9d637c6b553875189085c
```

Evaluar propósito, activación, entradas, preflight, procedimiento, límites, salidas, positivos, negativos, stop conditions, reparación, independencia, evidencia y continuidad.

### B. GitHub 150k+

Usar al menos una referencia comparable con estrellas verificadas. Referencias R8:

```text
Significant-Gravitas/AutoGPT — 185741 estrellas
classic/original_autogpt/CLAUDE.md

freeCodeCamp/freeCodeCamp — 453125 estrellas
curriculum/schema/challenge-schema.js
```

Extraer una práctica complementaria, no una similitud superficial. Si no existe hallazgo diferencial, registrar `NO_APPLICABLE_WOW_FOUND` con búsqueda y limitaciones.

## 10. Notas y semáforos

Cada artefacto recibe:

```text
NOTA_FINAL = MIN(NOTA_CLAUDE, NOTA_GITHUB, NOTA_TECNICA)
```

- verde: cada nota y final `> 9.5`;
- amarillo: final entre 8.5 y 9.5;
- rojo: final menor a 8.5 o bloqueo técnico;
- sin nota: falta uno de los tres componentes.

No usar promedios. Una nota editorial alta no compensa runtime, negativo, hashes o evidencia faltante.

## 11. Pruebas y rechazo de falsos PASS

Para cada cadena aplicable ejecutar:

```text
caso positivo
→ resultado esperado
caso negativo
→ rechazo correcto
BLOCKED/FAIL
→ cuando apliquen
```

PASS está prohibido si falta runtime aplicable, evidencia, hash, prueba negativa, referencia resoluble o independencia.

J12 compara tres conjuntos independientes:

```text
mapa canónico
→ archivos escritos
→ readback GitHub
```

J13 recalcula el porcentaje desde el ledger y exige todas las condiciones de cierre en cero. Un `100%` declarado no se acepta sin evidencia.

## 12. Persistencia y continuidad

Orden obligatorio:

1. readback Supabase y GitHub;
2. escribir solo en `feat/integral-story-creator-r8-forward`;
3. readback del archivo;
4. registrar commit, Git blob y SHA-256;
5. crear nueva versión Supabase sin borrar historial;
6. cambiar `is_current` objeto por objeto;
7. verificar SHA GitHub–Supabase;
8. registrar evento;
9. actualizar `AUDIT_CHECKLIST_R8.md`.

Ante concurrencia: no sobrescribir silenciosamente; crear versión nueva, reconciliar y registrar diferencia.

## 13. Salidas

```text
source_snapshot
screen_decomposition
coverage_report
story_pack[]
judge_result[]
execution_ledger
execution_report
github_readback_evidence
supabase_readback_evidence
```

Todos los objetos incluyen evidencia resoluble. Los resultados de jueces validan contra `schemas/judge-result.schema.json` v0.5.

## 14. Restricciones operativas

```text
repository: cristhianlujan/claude-persona-lf-patch
branch: feat/integral-story-creator-r8-forward
main_write: false
merge: false
pr_ready: false
pr_close: false
release: false
tag: false
production: false
runtime_enabled: false
```

Estados prohibidos: `VALIDATED`, `APPROVED`, `VIGENTE`, `PRODUCTION_READY` y `PRODUCTION_AUTHORIZED`.

## 15. Condiciones de cierre R8

Cerrar únicamente cuando:

```text
62/62 PASS_WITH_EVIDENCE
62/62 benchmark Claude ejecutado
62/62 benchmark GitHub 150k+ ejecutado
62/62 notas Claude, GitHub, técnica y final > 9.5
0 runtime bloqueados
0 pruebas positivas pendientes
0 pruebas negativas pendientes
0 assertions huérfanas
0 SHA mismatch
0 current duplicados
0 bloqueos abiertos
J01–J13 verificados
GitHub = Supabase
checklist actualizado
```

Único cierre permitido:

```text
R8_AUDIT_COMPLETE_WITH_DUAL_BENCHMARK_EVIDENCE
```

Este cierre no significa producción, merge, release ni runtime habilitado.

## 16. Casos de control

### Positivo

Una fuente íntegra produce inventario, Story Packs A–Q, pruebas exactas, J01–J13 PASS, hashes iguales y ledger binario 100%.

### Negativo

Rechazar cuando exista fuente sin hash, regla inventada, cobertura pendiente, fixture genérico, evidencia vacía, SHA distinto, rama incorrecta o cierre declarado al 100% con un step sin evidencia.

### Bloqueado

Bloquear ante fuente ausente, validador no disponible, conflicto de versión, escritura concurrente no reconciliada o dependencia material sin resolver.

## 17. Fuentes de diseño no normativas

- **Anthropic Skills:** evals realistas, grading programático, progressive disclosure y reparación iterativa.
- **AutoGPT:** estado explícito, límites de ejecución, persistencia y gotchas operativos.
- **freeCodeCamp:** constraints condicionales, unicidad y rechazo determinista.

Los contratos LF y la fuente operativa prevalecen ante cualquier diferencia.
