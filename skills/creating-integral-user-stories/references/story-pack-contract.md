# Contrato canónico del Story Pack

Versión operativa: `v0.3`. Juez asociado: `J03_STORY_CORE y J04–J10 según sección`.

## 1. Propósito

Definir las diecisiete secciones obligatorias que convierten una historia funcional en un artefacto implementable, verificable y trazable.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `screen_decomposition` | Resultado J02 con unidad funcional y decisión fuente. |
| `source_snapshot` | Versión y SHA-256 usados para derivar la historia. |
| `task_packet` | Alcance, worker, juez, assertions y evidencia requerida. |
| `registries` | Permisos, tokens, mensajes y catálogos autorizados disponibles. |

## 3. Preflight

Antes de aplicar este contrato:

1. Confirmar que las entradas obligatorias existen y pertenecen a la misma versión de fuente.
2. Resolver todas las referencias declaradas.
3. Confirmar que el alcance de lectura y escritura está autorizado.
4. Registrar contradicciones o datos ausentes antes de producir contenido.
5. Detenerse con `BLOCKED` cuando una condición bloqueante sea verdadera.

## 4. Procedimiento obligatorio

1. Crear A Identidad con códigos y trazabilidad exacta.
2. Crear B Núcleo funcional con un único resultado de negocio.
3. Completar C Interacción y D Campos sin inventar componentes o campos.
4. Derivar E Validaciones, F Observaciones y G Errores desde reglas fuente.
5. Definir H Seguridad y privacidad e I Estados e integridad.
6. Definir J Auditoría, K Tokens y mensajes, L Analytics y M Observabilidad como planos separados.
7. Completar N Responsive y accesibilidad con comportamiento verificable.
8. Derivar O Pruebas desde criterios, reglas y riesgos.
9. Registrar P Dependencias, riesgos y decisiones pendientes.
10. Registrar Q Jueces y evidencia; ningún worker se autoaprueba.

## 5. Reglas e invariantes

- Las 17 secciones deben existir; una sección no aplicable se representa explícitamente con razón, no se omite.
- Cada criterio de aceptación usa criterion_code, given, when, then y source_ref.
- Una afirmación sin source_ref no puede clasificarse CONFIRMED.
- Las secciones vacías no pueden usarse para simular completitud.
- Auditoría, analytics y observabilidad son planos distintos.
- El status solo puede ser CANDIDATO_READ_ONLY, PENDING_DECISION o BLOCKED dentro de este paquete.
- El Story Pack completo debe validar contra schemas/story-pack.schema.json.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json`.

La salida debe incluir referencias de fuente, conteos, assertions evaluadas, decisiones pendientes y rutas de evidencia. Una salida estructuralmente válida pero sin evidencia no es satisfactoria.

## 7. Assertions de paso

```text
required_sections_present = 17
stories_without_source_trace = 0
criteria_without_given_when_then = 0
fields_without_contract = 0
critical_rules_without_test = 0
judges_without_evidence = 0
```

## 8. Condiciones de bloqueo

```text
source_snapshot_unavailable = true
functional_unit_not_approved = true
material_business_rule_conflict = true
required_registry_unavailable_and_blocking = true
```

## 9. Ejemplo mínimo completo

```text
A identity             J audit
B core                 K tokens_messages
C interaction          L analytics
D fields               M observability
E validations          N responsive_accessibility
F observations         O tests
G errors               P dependencies_risks
H security_privacy     Q judges_evidence
I states
```

## 10. Reparación

Cuando una assertion falle, reparar exclusivamente el objeto asociado; no reducir el umbral, borrar la assertion ni modificar la fuente. Tras `retry_limit = 2`, devolver `BLOCKED` con la evidencia acumulada.

## 11. Handoff

Entregar al juez: versión de fuente, SHA-256, objetos procesados, conteos, assertions, fallas, decisiones pendientes, reparaciones aplicadas y evidence_refs resolubles.

## 12. Fuentes de diseño no normativas

- **microsoft/vscode** (~186,000 estrellas): `extensions/copilot/assets/prompts/skills/chronicle/SKILL.md`; patrones: prerrequisitos, workflows paso a paso, formatos de salida y stop conditions.
- **freeCodeCamp/freeCodeCamp** (~446,000 estrellas): `curriculum/schema/challenge-schema.js`; patrones: validación condicional, campos obligatorios, mensajes de error verificables.
- **Significant-Gravitas/AutoGPT** (~185,000 estrellas): `classic/original_autogpt/CLAUDE.md`; patrones: arquitectura explícita, ciclo operativo, estado, pruebas y gotchas.

Estas fuentes aportan patrones de ejecutabilidad, validación y pruebas. Los contratos LF y la fuente operativa prevalecen ante cualquier diferencia.
